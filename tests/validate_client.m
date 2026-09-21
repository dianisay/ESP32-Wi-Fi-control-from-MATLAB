function validate_client(port)
%VALIDATE_CLIENT Called only by the Python loopback simulator; never uses Wi-Fi.
host = "127.0.0.1";
report = test_esp32_wifi(host, port, "D8132A7D9198");
assert(report.passed);
test_esp32_protocol(host, port);
servoReport = test_esp32_servo(host, port);
assert(servoReport.passed);
for speed = [0 20 -20]
    report = run_continuous_servo(speed, 0.4, host, port, 1510);
    assert(report.neutralAcknowledged && report.commandCount >= 2 && report.pin == 25);
end
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
for value = [-101 101 NaN Inf 0.5]
    expectError(@() board.setServoSpeed(value));
end
for value = [1399 1601 NaN Inf 1500.5]
    expectError(@() board.setServoNeutral(value));
end
for value = [0 -1 31 NaN Inf]
    expectError(@() run_continuous_servo(20, value, host, port));
end
fprintf("PASS: signed speed, calibrated neutral and input bounds (simulated TCP only).\n");
end

function expectError(action)
rejected = false;
try
    action();
catch
    rejected = true;
end
assert(rejected, "Invalid input was accepted.");
end
