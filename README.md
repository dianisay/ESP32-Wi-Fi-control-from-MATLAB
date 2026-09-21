# ESP32 Wi-Fi control from MATLAB

This is custom Arduino firmware plus a MATLAB TCP client. It does **not** use
MATLAB's `arduino(...)` connection or the `arduinosetup` wizard. Uploading a
different sketch, including MATLAB's Arduino server, replaces this firmware.

## Hardware and requirements

- Detected chip: classic ESP32-D0WD-V3 revision 3.1, on **COM6** during setup.
- MATLAB R2025b is installed. Only base MATLAB (`tcpclient`, `serialport`) is used.
- Firmware targets `esp32:esp32:esp32` (ESP32 Dev Module), Arduino ESP32 core 2.0.11.
- Default LED: **GPIO2, active high**. Electronic identification cannot confirm
  the carrier board or its LED wiring. A power LED is not software controllable.
- No external GPIO circuitry was connected during the initial LED setup.
- The servo extension uses Arduino ESP32 core **2.x** LEDC APIs (tested with
  2.0.11). Select that core version; Arduino ESP32 core 3.x changed these APIs.

## Connect

1. Power the ESP32 through USB. USB is for power and initial credential discovery;
   all LED commands and connection tests use TCP over Wi-Fi.
2. Make this folder MATLAB's current folder. Close Arduino Serial Monitor first.
3. Obtain this board's Wi-Fi credentials locally:

   ```matlab
   info = esp32_usb_info("COM6");
   fprintf("Network: %s\nPassword: %s\n", info.ssid, info.password);
   ```

4. In Windows Wi-Fi settings, connect to the displayed `ESP32-MATLAB-...` network.
   Select **stay connected** if Windows warns that it has no Internet access.
   The AP intentionally supplies no Internet. Connecting may disconnect your
   usual Wi-Fi; another adapter or Ethernet can preserve Internet access.
5. Run:

   ```matlab
   report = test_esp32_wifi(info.host, info.port, info.deviceId);
   blink_esp32(10);
   test_esp32_protocol;
   ```

After the first setup, USB credential discovery is unnecessary:

```matlab
report = test_esp32_wifi;  % 192.168.4.1, TCP port 3333
blink_esp32(10);
```

The firmware generates a random password on first boot and stores it in ESP32
NVS. It survives power cycles and ordinary sketch uploads. Do not publish it.
Erasing all flash removes the saved password. Only the USB `WIFI` command reveals
the password; it is not exposed by the network protocol.

## Manual control

```matlab
b = Esp32Wifi;
b.ping()             % Round-trip time in seconds
b.setLed(true);      % ON
pause(1)
b.setLed(false);     % OFF
s = b.getState()
delete(b);           % Turn off and release TCP connection
clear b
```

Commands must be less than 10 seconds apart. After 10 seconds without a
complete command, firmware turns the LED off and closes the client. Create a new
`Esp32Wifi` object to reconnect. Only one TCP client is supported. Close an old
MATLAB connection before running another test.

## Continuous-rotation MG996R servo

**Preparation only: the servo extension has not been uploaded to the board or
tested with a physical servo.** The original LED firmware does not understand
servo commands; upload the updated sketch only after sorting out the wiring.
Disconnect the servo while uploading and during protocol-only tests.

This code is for a **continuous-rotation** unit, not a standard positional
MG996R. Check the seller's specification or modification. It controls signed
speed commands, not angle. A continuous servo cannot be commanded to a specific
angle without additional position sensing and control.

### Connections and power

Disconnect all power before wiring.

| Connection | Destination |
| --- | --- |
| Servo signal (usually orange/yellow) | ESP32 **GPIO25 / D25** |
| Servo positive (usually red) | External regulated **5 V** supply positive |
| Servo ground (usually brown/black) | Supply negative **and ESP32 GND** |
| ESP32 power | USB, as before |
| Onboard LED output | **GPIO2**, unchanged |
| GPIO12 / D12 and GPIO13 / D13 | **Unused** |

Use a regulated 5 V supply rated for **at least 3 A for one MG996R**; verify the
actual servo's voltage and stall-current specifications (clones vary). Use
current-rated power leads/connectors. Thin signal jumpers are not suitable for
carrying several amps. Avoid feeding servo power through a solderless breadboard.
Connect the supply ground to ESP32 GND, but do not connect its positive rail to
the USB-powered ESP32's 5 V/VIN pin: that could back-feed USB.

**Never power the servo from a GPIO or the ESP32's 3.3 V pin. Do not use the PC's
USB/ESP32 5 V rail for this MG996R setup.** Software cannot compensate for the
wrong power connection. You need suitable wiring and a supply before testing.

### First test, then direction/speed control

Keep the horn/linkage unloaded, secure the servo body, and keep fingers clear.
After uploading the updated firmware, reconnect to the same ESP32 Wi-Fi network.
In this folder in MATLAB:

```matlab
run_continuous_servo(0, 3);    % First check: neutral, no intended rotation
```

If it creeps, do not continue to the motion tests yet. Continuous servos often
need neutral calibration: adjust their trim as specified by the manufacturer,
or try small 5-10 microsecond changes to the last argument below:

```matlab
run_continuous_servo(0, 3, "192.168.4.1", 3333, 1510);
```

Permitted neutral is 1400-1600 us; default is 1500 us. This setting is not saved
across board resets, and the demo explicitly sets it on each run. Pass your
calibrated neutral value on **every** subsequent call if it differs from 1500.

```matlab
neutralUs = 1500;  % Replace with your physically verified stop value.
run_continuous_servo(20, 2, "192.168.4.1", 3333, neutralUs);
run_continuous_servo(-20, 2, "192.168.4.1", 3333, neutralUs);
```

Positive and negative mean opposite directions; which is clockwise depends on
the servo. Zero means neutral. Signed command range is -100 to +100 percent,
not a percentage of a measured RPM. The mapping is:

`pulse_us = neutral_us + 4 * speed_percent`, at **50 Hz**.

With the default neutral, endpoints are 1100 and 1900 us. Speed response and
deadband are servo-dependent and not necessarily linear. The demo runs for at
most 30 seconds per call and requests neutral on completion or Ctrl+C cleanup.
MATLAB/Windows timing is not hard real time.

The board starts with **no servo pulses**. After a servo speed command it keeps
generating PWM, returning to the configured neutral if no new speed command
arrives for **500 ms**, or when the TCP disconnect is detected. The demo renews
commands approximately every 100 ms. PING, LED, and status commands do not renew
the motion lease. The previous 10-second TCP idle timeout still applies.

**Neutral is a stop request, not a guaranteed physical stop or power cut.**
It depends on calibration, servo behavior, firmware health and correct power.
Do not use this demo for load-bearing or hazardous machinery. Keep a physical
way to disconnect servo power accessible.

For your own MATLAB program, `Esp32Wifi` also exposes `getServoInfo`,
`setServoNeutral`, `setServoSpeed`, `stopServo`, and `getServoState`.
`setServoSpeed` must be refreshed before the 500 ms deadline. Returned state
reports the PWM command, not measured motion.

With the **servo physically unplugged**, `test_esp32_servo` checks full-range
command mapping, neutral adjustment, the motion lease and client cleanup.
Do not run that protocol test with the servo attached.

The tests verify the device handshake, nonce-matched PING replies, GPIO output
readback, and reconnection. **They cannot prove light was emitted**: visually
check that the programmable LED blinks five times. If it does not, determine the
board's schematic/model before changing `LED_PIN` or `LED_ACTIVE_HIGH` in the
sketch. Do not scan arbitrary pins. The protocol regression test currently
expects GPIO2's active-high configuration; update its expected levels if changing
the polarity.

## Validation without hardware

The servo-enabled sketch compiled successfully with Arduino ESP32 core 2.0.11.
The MATLAB client also passed loopback TCP regression tests for existing LED
commands, speed/pulse mapping, calibrated neutral, cleanup, simulated timeout
handling, and invalid-input rejection. These tests do **not** validate the
ESP32's physical PWM waveform, real firmware timing, servo power, or rotation.

To repeat the client-only tests from this folder using Python and MATLAB on PATH:

```powershell
python .\tests\validate_client.py
```

The simulator binds only to `127.0.0.1`; it never connects to or programs the
ESP32 and does not require its Wi-Fi network.

## Rebuild/upload

In Arduino IDE, install "esp32 by Espressif Systems" via Boards Manager if needed.
For the servo extension, select version **2.0.11**, not 3.x.
Open [the sketch](firmware/esp32_matlab_wifi/esp32_matlab_wifi.ino), choose
**ESP32 Dev Module**, choose the current USB port, and upload. The installed
MATLAB ESP32 toolchain can also compile/upload without installing another core:

```powershell
$cli = 'C:\ProgramData\MATLAB\SupportPackages\R2025b\aCLI\arduino-cli.exe'
$config = 'C:\ProgramData\MATLAB\SupportPackages\R2025b\aCLI\arduino-cli.yaml'
& $cli compile --config-file $config --fqbn esp32:esp32:esp32 --output-dir .\build .\firmware\esp32_matlab_wifi
if ($LASTEXITCODE -eq 0) {
    & $cli upload --config-file $config --fqbn esp32:esp32:esp32 --port COM6 --input-dir .\build .\firmware\esp32_matlab_wifi
}
```

## Troubleshooting

- **Cannot connect:** check Windows is on the ESP32 network and has a
  `192.168.4.x` address. Target `192.168.4.1:3333`, not COM6.
- **USB port busy:** close Serial Monitor, old `serialport` objects, and other
  MATLAB sessions holding the port. COM numbers can change.
- **Upload stuck at Connecting:** hold BOOT while upload starts, release once
  writing begins. Use EN/RESET after upload if necessary.
- **Timeout after a pause:** the 10-second idle fail-safe closed the connection;
  delete the old object and reconnect.
- **VPN/subnet conflict:** a route for `192.168.4.0/24` elsewhere may interfere.
  Do not disable the firewall globally; allow MATLAB on the appropriate local
  network if prompted.
- **Only a power LED stays on:** the power LED is not controllable. The actual
  carrier board may lack a programmable LED.

This is a local lab protocol, not a safety controller. TCP is not TLS-encrypted
and has no separate application authentication; anyone with the AP password can
control the LED and servo. Do not forward its port to the Internet. The servo
example is for an unloaded bench test only, not production machinery; add
appropriate authentication and independent hardware safety measures for other uses.
