function test_esp32_protocol(host, port)
%TEST_ESP32_PROTOCOL Exercise framing, invalid commands and disconnect fail-safe.
arguments
    host (1,1) string = "192.168.4.1"
    port (1,1) double {mustBeInteger, mustBeInRange(port,1,65535)} = 3333
end
connection = tcpclient(host, port, "Timeout", 3, "ConnectTimeout", 5);
configureTerminator(connection, "LF");
expect("LED 0", "OK LED 0 LEVEL 0");
expect("LED 2", "ERR BAD_COMMAND");
expect("PING bad token", "ERR BAD_TOKEN");
expect(string(repmat('X', 1, 81)), "ERR BAD_LINE");
expect("PING recovered", "OK PONG recovered");
write(connection, uint8('PI'));
pause(0.05);
write(connection, uint8(sprintf('NG fragmented\nPING bundled\n')));
assert(strip(readline(connection)) == "OK PONG fragmented", "Fragmented line failed.");
assert(strip(readline(connection)) == "OK PONG bundled", "Bundled line failed.");
expect("LED 1", "OK LED 1 LEVEL 1");
connection = [];
pause(0.5);
connection = tcpclient(host, port, "Timeout", 3, "ConnectTimeout", 5);
configureTerminator(connection, "LF");
expect("STATE", "OK LED 0 LEVEL 0");
expect("LED 1", "OK LED 1 LEVEL 1");
pause(11);
assert(strip(readline(connection)) == "ERR IDLE_TIMEOUT", "Idle timeout was not reported.");
connection = [];
pause(0.25);
connection = tcpclient(host, port, "Timeout", 3, "ConnectTimeout", 5);
configureTerminator(connection, "LF");
expect("STATE", "OK LED 0 LEVEL 0");
fprintf("PASS: framing, rejection, recovery, disconnect and 10-second idle fail-safe.\n");

    function expect(command, expected)
        writeline(connection, command);
        actual = strip(readline(connection));
        assert(~ismissing(actual) && actual == expected, ...
            "ESP32:ProtocolTest", "Unexpected response to %s: %s", command, actual);
    end
end
