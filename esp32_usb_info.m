function info = esp32_usb_info(port)
%ESP32_USB_INFO Read AP credentials over USB. Does not program the board.
%   info = esp32_usb_info("COM6"); disp(info)
%   Do not share the password or save it in source control.
arguments
    port (1,1) string = "COM6"
end
connection = serialport(port, 115200, "Timeout", 2);
cleanup = onCleanup(@() delete(connection));
configureTerminator(connection, "LF");
pause(3);
flush(connection);
writeline(connection, "WIFI");
timer = tic;
while toc(timer) < 10
    if connection.NumBytesAvailable == 0
        pause(0.05);
        continue
    end
    line = strip(readline(connection));
    if ismissing(line)
        error("ESP32:UsbTimeout", "Incomplete USB response from %s.", port);
    end
    if startsWith(line, "ERROR ") || startsWith(line, "ERR ")
        error("ESP32:UsbFirmware", "%s", line);
    end
    if startsWith(line, "{")
        info = jsondecode(line);
        required = ["ssid","password","host","port","deviceId","ledPin","activeHigh"];
        if ~all(isfield(info, required))
            error("ESP32:UsbProtocol", "USB configuration response is missing required fields.");
        end
        return
    end
end
error("ESP32:UsbTimeout", ...
    "No Wi-Fi configuration received from %s. Check firmware, port and the EN/RESET button.", port);
end
