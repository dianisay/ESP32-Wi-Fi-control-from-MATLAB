function report = run_continuous_servo(speedPercent, durationSeconds, host, port, neutralUs)
%RUN_CONTINUOUS_SERVO Run an unloaded continuous-rotation MG996R, then neutral.
%   run_continuous_servo(0, 3)    % First test: check neutral, no intended rotation.
%   run_continuous_servo(20, 2)   % One direction for two seconds.
%   run_continuous_servo(-20, 2)  % The opposite direction.
%   Correct external power and updated firmware are REQUIRED. Signal: GPIO25.
%   Percent is a signed PWM command, NOT measured speed or a target angle.
arguments
    speedPercent (1,1) double {mustBeInteger, mustBeInRange(speedPercent,-100,100)} = 0
    durationSeconds (1,1) double {mustBeFinite, mustBePositive, mustBeLessThanOrEqual(durationSeconds,30)} = 3
    host (1,1) string = "192.168.4.1"
    port (1,1) double {mustBeInteger, mustBeInRange(port,1,65535)} = 3333
    neutralUs (1,1) double {mustBeInteger, mustBeInRange(neutralUs,1400,1600)} = 1500
end
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
info = board.getServoInfo();
board.stopServo();
board.setServoNeutral(neutralUs);
fprintf("Continuous servo on GPIO%d: neutral %d us, command %+d%% for %.1f s.\n", ...
    info.pin, neutralUs, speedPercent, durationSeconds);
fprintf("Keep the horn unloaded. Neutral may require calibration; PWM is not motion feedback.\n");

board.setServoSpeed(0);
pause(0.5);
timer = tic;
commandCount = 0;
while toc(timer) < durationSeconds
    board.setServoSpeed(speedPercent);
    commandCount = commandCount + 1;
    pause(min(0.1, max(0, durationSeconds - toc(timer))));
end
state = board.stopServo();
assert(state.pulseUs == neutralUs, "ESP32:ServoStop", "Neutral pulse was not confirmed.");
pause(0.3);
report = struct("deviceId", board.DeviceId, "pin", info.pin, ...
    "speedPercent", speedPercent, "requestedDurationSeconds", durationSeconds, ...
    "neutralUs", neutralUs, "commandCount", commandCount, ...
    "neutralAcknowledged", true, "physicalStopVerified", false);
fprintf("Neutral command acknowledged. Confirm physically that rotation stopped.\n");
end
