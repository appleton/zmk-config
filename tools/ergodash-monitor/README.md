# ErgoDash USB Monitor

A native macOS menu bar app for this repo's dongle firmware. No packages,
Bluetooth connection to the Mac, or background helper are required.
Build with Apple's command-line developer tools (Swift) on macOS 13+:

```sh
sh tools/ergodash-monitor/build.sh
open "tools/ergodash-monitor/build/ErgoDash USB Monitor.app"
```

You can copy the built `.app` to Applications and add it to Login Items in
System Settings. The build script signs it locally with an ad-hoc signature.
It builds for the Mac's architecture.

The menu bar shows `L 84%⚡ R 62%`. Click it for battery voltage, USB power
status, signal strength at the dongle in dBm, and the age of the battery
reading. A value closer to zero is a stronger received signal. RSSI alone
does not measure interference, packet loss or typing latency.

The ⚡ symbol means **USB power detected on that half**. It does not mean that
the battery is actively charging: nice!nano v2 does not expose its charger
status to the MCU. Its physical charging LED remains the indicator of actual
charging. Voltage-derived battery percentages can rise prematurely while
charging. Accurate state of charge or charging/full status would require
additional sensing hardware.

Flash the matching normal firmware onto all three devices. Existing split
bonds can be retained. Physical left/right IDs are built into the halves.
The app supports one attached dongle; it selects the first matching interface.
This vendor HID interface does not listen to keystrokes. macOS may request
Input Monitoring permission when opening HID devices; allow it for this app
if access is denied, then quit and relaunch.

Battery voltage is sampled every 30 seconds, including while idle. The dongle
queries telemetry and RSSI every 5 seconds and sends USB snapshots every
second. It also supports feature reads so the app can get a snapshot after
the dongle is already connected. Disconnected halves show `—`; missing/stale
samples show `?`. A sample older than 90 seconds is stale. The app hides its
readings if it has not received a USB report for 10 seconds. The last known
percentage is never presented as live after a disconnect.

Firmware polling adds some radio/ADC work, so battery runtime should be
checked on hardware. The peripheral sample task shares ZMK's low-priority
ADC workqueue to prevent overlapping battery conversions. The dongle uses a
separate workqueue for telemetry and HCI RSSI requests.

## Verification

```sh
clang -Wall -Wextra -Werror tests/protocol_test.c -o /tmp/ergodash-protocol-test
/tmp/ergodash-protocol-test
sh tools/ergodash-monitor/build.sh
open "tools/ergodash-monitor/build/ErgoDash USB Monitor.app" --args --demo
```

The C tests cover GATT packet validation and voltage conversion. The build
script also runs Swift decoder tests, including signed RSSI, zero versus
unknown battery levels, malformed data, disconnected halves and stale data.
`--demo` shows labelled sample data without opening USB devices.

Hardware acceptance checks after flashing:

1. Keep a spare keyboard available and flash the three normal firmware files.
2. Confirm typing works through USB with Bluetooth on the Mac turned off.
3. Check that L/R show separate percentages and voltages within 40 seconds.
4. Plug a charging cable into one half; only that half should show ⚡ within
   about 5 seconds. Battery samples should keep updating while idle/charging.
5. Unplug its charging cable and check that ⚡ disappears.
6. Move each half further from the dongle and check its RSSI changes.
7. Turn off one half; its reading should change to disconnected once the BLE
   supervision timeout expires. Turn it on and check automatic recovery.
8. Quit/reopen the app with the dongle already connected, then unplug/replug
   the dongle. Verify readings recover in both cases.

## Wire format (version 1)

The dongle uses VID/PID `1d50:615e` and a separate HID application collection
with usage page `ff60`, usage `61`. The existing keyboard interface is unchanged.
Input and feature report ID 1 have a 19-byte payload (20 bytes including ID):

| Byte | Value |
| --- | --- |
| 0 | Report ID, 1 |
| 1 | Protocol version, 1 |
| 2–10 | Left half record |
| 11–19 | Right half record |

Each nine-byte record contains:

| Offset | Value |
| --- | --- |
| 0 | Flags: bit 0 battery valid, bit 1 USB powered, bit 2 connected, bit 3 RSSI valid |
| 1 | Percentage 0–100; 255 means unknown |
| 2–3 | Battery millivolts, unsigned little-endian |
| 4–5 | Battery sample age in seconds; 65535 means unknown |
| 6 | RSSI in dBm, signed 8-bit; 127 means unavailable |
| 7–8 | RSSI sample age in seconds; 65535 means unknown |

Peripherals expose an encrypted read-only characteristic
`079a1701-697a-4ba7-b9d5-b4d2bf4e7f90` on their existing split BLE connection.
Its eight bytes are version, physical side (0 left / 1 right), battery/USB
flags, percentage, millivolts (u16 LE), and sample age (u16 LE). No additional
connections are made. RSSI is read locally by the dongle using HCI Read RSSI.
