function blink_esp32(cycles, host, port)
%BLINK_ESP32 Blink the onboard LED through Wi-Fi, then leave it OFF.
arguments
    cycles (1,1) double {mustBeInteger, mustBeInRange(cycles,1,1000)} = 10
    host (1,1) string = "192.168.4.1"
    port (1,1) double {mustBeInteger, mustBeInRange(port,1,65535)} = 3333
end
board = Esp32Wifi(host, port);
cleanup = onCleanup(@() delete(board));
fprintf("Blinking GPIO%d on ESP32 %s using Wi-Fi.\n", board.LedPin, board.DeviceId);
for index = 1:cycles
    board.setLed(true);
    pause(0.5);
    board.setLed(false);
    pause(0.5);
end
end
