function report = test_esp32_servo(host, port)
%TEST_ESP32_SERVO Test PWM commands with the servo physically UNPLUGGED.
%   Sends full-range commands to verify the protocol. Do NOT attach a servo.
%   Confirms reported PWM state, not waveform timing or physical rotation.
arguments
    host (1,1) string = "192.168.4.1"
    port (1,1) double {mustBeInteger, mustBeInRange(port,1,65535)} = 3333
end
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
info = board.getServoInfo();
board.stopServo();
for neutral = [1400 1500 1600]
    board.setServoNeutral(neutral);
    for speed = [-100 -20 0 20 100]
        state = board.setServoSpeed(speed);
        assert(state.pulseUs == neutral + 4 * speed, "Incorrect pulse mapping.");
    end
    board.stopServo();
end
board.setServoNeutral(1500);
board.setServoSpeed(20);
timer = tic;
while toc(timer) < 0.7
    board.ping();
    pause(0.05);
end
state = board.getServoState();
assert(state.speedPercent == 0 && state.pulseUs == 1500, ...
    "PING traffic incorrectly renewed the servo command lease.");

board.setServoSpeed(-20);
clear cleanup
pause(0.25);
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
state = board.getServoState();
assert(state.speedPercent == 0 && state.pulseUs == 1500, "Cleanup failed to request neutral.");
report = struct("passed", true, "pin", info.pin, "leaseMs", info.leaseMs, ...
    "physicalMotionTested", false);
fprintf("PASS: GPIO25, pulse mapping, neutral adjustment, command lease and cleanup.\n");
end
