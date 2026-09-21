classdef Esp32Wifi < handle
    %ESP32WIFI Control the accompanying firmware over Wi-Fi, not USB.
    properties (SetAccess = private)
        DeviceId
        LedPin
        ActiveHigh
    end
    properties (Access = private)
        Connection
        ServoInfo = []
        ServoUsed = false
    end
    methods
        function obj = Esp32Wifi(host, port)
            arguments
                host (1,1) string = "192.168.4.1"
                port (1,1) double {mustBeInteger, mustBeInRange(port,1,65535)} = 3333
            end
            obj.Connection = tcpclient(host, port, "Timeout", 3, "ConnectTimeout", 5);
            configureTerminator(obj.Connection, "LF");
            reply = obj.request("HELLO");
            fields = regexp(reply, ...
                '^OK ESP32_MATLAB 1 ([0-9A-F]{12}) GPIO (\d+) ACTIVE_HIGH ([01])$', ...
                'tokens', 'once');
            if isempty(fields)
                obj.Connection = [];
                error("ESP32:Handshake", "Unexpected firmware handshake: %s", reply);
            end
            obj.DeviceId = string(fields{1});
            obj.LedPin = str2double(fields{2});
            obj.ActiveHigh = logical(str2double(fields{3}));
        end

        function seconds = ping(obj)
            token = string(sprintf('%08x%08x', randi([0, 2^31-1], 1, 2)));
            timer = tic;
            reply = obj.request("PING " + token);
            seconds = toc(timer);
            if reply ~= "OK PONG " + token
                error("ESP32:Ping", "Unexpected PING reply: %s", reply);
            end
        end

        function state = setLed(obj, on)
            arguments
                obj
                on (1,1) logical
            end
            state = obj.parseState(obj.request("LED " + string(double(on))));
            if state.on ~= on
                error("ESP32:LedState", "Board did not acknowledge the requested LED state.");
            end
        end

        function state = getState(obj)
            state = obj.parseState(obj.request("STATE"));
        end

        function info = getServoInfo(obj)
            % Requires the servo-enabled firmware, not the original LED-only build.
            info = obj.parseServoInfo(obj.request("SERVO INFO"));
            obj.ServoInfo = info;
        end

        function info = setServoNeutral(obj, pulseUs)
            arguments
                obj
                pulseUs (1,1) double {mustBeInteger, mustBeInRange(pulseUs,1400,1600)}
            end
            obj.ServoUsed = true;
            info = obj.parseServoInfo(obj.request("SERVO NEUTRAL " + string(pulseUs)));
            if info.neutralUs ~= pulseUs
                error("ESP32:ServoNeutral", "Neutral pulse was not acknowledged.");
            end
            obj.ServoInfo = info;
        end

        function state = setServoSpeed(obj, percent)
            % Renew at least every 500 ms; run_continuous_servo does this for you.
            arguments
                obj
                percent (1,1) double {mustBeInteger, mustBeInRange(percent,-100,100)}
            end
            if isempty(obj.ServoInfo)
                obj.getServoInfo();
            end
            obj.ServoUsed = true;
            state = obj.parseServoState(obj.request("SERVO " + string(percent)));
            expectedPulse = obj.ServoInfo.neutralUs + fix(percent * obj.ServoInfo.spanUs / 100);
            if state.speedPercent ~= percent || state.pulseUs ~= expectedPulse || ~state.enabled
                error("ESP32:ServoCommand", "Servo PWM command was not acknowledged correctly.");
            end
        end

        function state = stopServo(obj)
            state = obj.parseServoState(obj.request("SERVO STOP"));
            if state.speedPercent ~= 0
                error("ESP32:ServoStop", "Servo neutral command was not acknowledged.");
            end
        end

        function state = getServoState(obj)
            % This is commanded PWM state, not measured rotation or speed.
            state = obj.parseServoState(obj.request("SERVO STATE"));
        end

        function delete(obj)
            if ~isempty(obj.Connection)
                try
                    if obj.ServoUsed
                        obj.stopServo();
                    end
                    obj.setLed(false);
                catch exception
                    warning("ESP32:Cleanup", ...
                        "Could not confirm output cleanup: %s. Servo firmware requests " + ...
                        "neutral after 500 ms without a speed command; LED timeout is 10 s.", ...
                        exception.message);
                end
                obj.Connection = [];
            end
        end
    end
    methods (Access = private)
        function info = parseServoInfo(~, reply)
            fields = regexp(reply, ...
                '^OK SERVO GPIO (\d+) NEUTRAL_US (\d+) SPAN_US (\d+) LEASE_MS (\d+)$', ...
                'tokens', 'once');
            if isempty(fields)
                error("ESP32:ServoProtocol", "Unexpected servo information: %s", reply);
            end
            values = str2double(fields);
            if values(1) ~= 25 || values(2) < 1400 || values(2) > 1600 || ...
                    values(3) ~= 400 || values(4) ~= 500
                error("ESP32:ServoConfiguration", "Unsupported servo configuration: %s", reply);
            end
            info = struct("pin", values(1), "neutralUs", values(2), ...
                "spanUs", values(3), "leaseMs", values(4));
        end

        function state = parseServoState(~, reply)
            fields = regexp(reply, ...
                '^OK SERVO SPEED (-?\d+) PULSE_US (\d+) ENABLED ([01])$', ...
                'tokens', 'once');
            if isempty(fields)
                error("ESP32:ServoProtocol", "Unexpected servo response: %s", reply);
            end
            values = str2double(fields);
            if abs(values(1)) > 100 || values(2) < 1000 || values(2) > 2000
                error("ESP32:ServoProtocol", "Servo response is outside permitted bounds: %s", reply);
            end
            state = struct("speedPercent", values(1), "pulseUs", values(2), ...
                "enabled", logical(values(3)));
        end

        function reply = request(obj, command)
            if isempty(obj.Connection)
                error("ESP32:Closed", "The connection has been closed; create a new Esp32Wifi object.");
            end
            try
                writeline(obj.Connection, command);
                reply = strip(readline(obj.Connection));
                if ismissing(reply) || strlength(reply) == 0
                    error("ESP32:Timeout", "No complete response within the 3-second timeout.");
                end
                if startsWith(reply, "ERR ")
                    error("ESP32:Remote", "Board rejected command: %s", reply);
                end
            catch exception
                % A timeout may leave an old reply queued; never reuse that stream.
                obj.Connection = [];
                rethrow(exception);
            end
        end

        function state = parseState(obj, reply)
            fields = regexp(reply, '^OK LED ([01]) LEVEL ([01])$', 'tokens', 'once');
            if isempty(fields)
                error("ESP32:Protocol", "Unexpected LED response: %s", reply);
            end
            state = struct("on", logical(str2double(fields{1})), ...
                "level", logical(str2double(fields{2})));
            if state.level ~= (state.on == obj.ActiveHigh)
                error("ESP32:Readback", "GPIO readback does not match the commanded output.");
            end
        end
    end
end
