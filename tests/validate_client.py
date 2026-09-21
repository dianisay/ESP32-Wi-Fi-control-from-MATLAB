"""Exercise the MATLAB client with a loopback simulator, never real hardware."""
import pathlib
import re
import shutil
import socket
import subprocess
import threading
import time
import traceback


class Simulator:
    def __init__(self):
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(0.1)
        self.port = self.listener.getsockname()[1]
        self.shutdown = threading.Event()
        self.errors = []
        self.commands = []
        self.led = self.speed = self.enabled = 0
        self.neutral = self.pulse = 1500
        self.last_speed = 0

    def stop_servo(self):
        self.speed = 0
        self.pulse = self.neutral

    def info(self):
        return f"OK SERVO GPIO 25 NEUTRAL_US {self.neutral} SPAN_US 400 LEASE_MS 500"

    def state(self):
        return f"OK SERVO SPEED {self.speed} PULSE_US {self.pulse} ENABLED {self.enabled}"

    def reply(self, line):
        self.commands.append(line)
        if len(line) > 80:
            return "ERR BAD_LINE"
        if line == "HELLO":
            return "OK ESP32_MATLAB 1 D8132A7D9198 GPIO 2 ACTIVE_HIGH 1"
        if re.fullmatch(r"PING [A-Za-z0-9_-]{1,32}", line):
            return "OK PONG " + line[5:]
        if line.startswith("PING "):
            return "ERR BAD_TOKEN"
        if line in ("LED 0", "LED 1"):
            self.led = int(line[-1])
        elif line == "SERVO INFO":
            return self.info()
        elif line == "SERVO STATE":
            return self.state()
        elif line == "SERVO STOP":
            self.stop_servo()
            return self.state()
        elif re.fullmatch(r"SERVO NEUTRAL \d{4}", line):
            value = int(line[14:])
            if not 1400 <= value <= 1600:
                return "ERR NEUTRAL_RANGE_1400_1600"
            if self.speed:
                return "ERR STOP_SERVO_FIRST"
            self.neutral = value
            self.stop_servo()
            return self.info()
        elif re.fullmatch(r"SERVO -?\d{1,3}", line):
            value = int(line[6:])
            if abs(value) > 100:
                return "ERR SERVO_RANGE_MINUS100_100"
            self.speed = value
            self.pulse = self.neutral + 4 * value
            self.enabled = 1
            self.last_speed = time.monotonic()
            return self.state()
        elif line != "STATE":
            return "ERR BAD_COMMAND"
        return f"OK LED {self.led} LEVEL {self.led}"

    def serve(self):
        try:
            while not self.shutdown.is_set():
                try:
                    connection, _ = self.listener.accept()
                except socket.timeout:
                    continue
                with connection:
                    connection.settimeout(0.02)
                    buffer = b""
                    last_activity = time.monotonic()
                    try:
                        while not self.shutdown.is_set():
                            now = time.monotonic()
                            if self.speed and now - self.last_speed >= 0.5:
                                self.stop_servo()
                            if now - last_activity >= 10:
                                self.stop_servo()
                                self.led = 0
                                print(f"Simulator idle timeout; last command: {self.commands[-1]}")
                                connection.sendall(b"ERR IDLE_TIMEOUT\n")
                                break
                            try:
                                data = connection.recv(1024)
                            except socket.timeout:
                                continue
                            if not data:
                                break
                            buffer += data
                            while b"\n" in buffer:
                                line, buffer = buffer.split(b"\n", 1)
                                last_activity = time.monotonic()
                                reply = self.reply(line.decode("ascii").rstrip("\r"))
                                connection.sendall((reply + "\n").encode("ascii"))
                    except (ConnectionResetError, BrokenPipeError):
                        print("Simulator: client closed TCP connection.")
                    finally:
                        self.stop_servo()
                        self.led = 0
        except Exception:
            self.errors.append(traceback.format_exc())


def main():
    matlab = shutil.which("matlab")
    if matlab is None:
        raise RuntimeError("MATLAB must be installed and available on PATH.")
    root = pathlib.Path(__file__).resolve().parent.parent
    simulator = Simulator()
    worker = threading.Thread(target=simulator.serve)
    worker.start()
    matlab_root = str(root).replace("'", "''")
    code = f"cd('{matlab_root}'); addpath('tests'); validate_client({simulator.port});"
    try:
        result = subprocess.run(
            [matlab, "-batch", code], capture_output=True, text=True, timeout=180
        )
        print(result.stdout)
        print(result.stderr)
    finally:
        simulator.shutdown.set()
        worker.join(timeout=5)
        simulator.listener.close()
    assert not worker.is_alive(), "Simulator failed to stop"
    assert not simulator.errors, "\n".join(simulator.errors)
    assert result.returncode == 0, f"MATLAB exited with {result.returncode}"
    assert simulator.speed == 0 and simulator.led == 0
    for line in simulator.commands:
        match = re.fullmatch(r"SERVO (-?\d+)", line)
        if match:
            assert -100 <= int(match[1]) <= 100, line
    print(f"PASS: {len(simulator.commands)} loopback commands; final outputs neutral/off.")
    print("No ESP32 connection or upload performed; this does not test firmware or mechanics.")


if __name__ == "__main__":
    main()
