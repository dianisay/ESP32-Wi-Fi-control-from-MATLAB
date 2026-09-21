function report = test_esp32_wifi(host, port, expectedDeviceId)
%TEST_ESP32_WIFI Verify identity, 20 TCP round trips, LED readback and reconnect.
%   report = test_esp32_wifi;
%   These tests require the PC to be connected to the ESP32 access point.
arguments
    host (1,1) string = "192.168.4.1"
    port (1,1) double {mustBeInteger, mustBeInRange(port,1,65535)} = 3333
    expectedDeviceId (1,1) string = ""
end
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
deviceId = board.DeviceId;
if expectedDeviceId ~= ""
    assert(deviceId == upper(expectedDeviceId), "ESP32:Identity", ...
        "Connected to a different ESP32 than expected.");
end
fprintf("Connected over TCP to %s:%d, ESP32 %s, GPIO%d.\n", ...
    host, port, deviceId, board.LedPin);

roundTripMs = zeros(20, 1);
for index = 1:numel(roundTripMs)
    roundTripMs(index) = 1000 * board.ping();
end
fprintf("PASS: 20/20 nonce-verified round trips (mean %.1f ms, max %.1f ms).\n", ...
    mean(roundTripMs), max(roundTripMs));

fprintf("Watch the board: five ON/OFF cycles, 0.5 seconds per state.\n");
for index = 1:5
    board.setLed(true);
    pause(0.5);
    state = board.getState();
    assert(state.on, "ESP32:LedOn", "LED state was not ON.");
    board.setLed(false);
    pause(0.5);
    state = board.getState();
    assert(~state.on, "ESP32:LedOff", "LED state was not OFF.");
end
fprintf("PASS: 10 LED commands and GPIO readbacks. Optical confirmation is separate.\n");
ledPin = board.LedPin;
clear cleanup
pause(0.25);
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
assert(board.DeviceId == deviceId, "ESP32:Reconnect", "Device changed after reconnect.");
board.ping();
state = board.getState();
assert(~state.on, "ESP32:ReconnectLed", "LED should be OFF after reconnect.");
fprintf("PASS: disconnected and reconnected over Wi-Fi; LED is OFF.\n");
report = struct("passed", true, "deviceId", deviceId, "host", host, ...
    "port", port, "ledPin", ledPin, "roundTripMs", roundTripMs, ...
    "ledTransitions", 10, "reconnected", true, "opticalLedVerified", false);
end
