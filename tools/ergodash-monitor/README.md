# ErgoDash USB Monitor

A compact macOS desktop card, native WidgetKit widget and USB collector for
this repo's dongle firmware. Build with Apple's developer tools on macOS 14+:

```sh
sh tools/ergodash-monitor/build.sh
open "tools/ergodash-monitor/build/ErgoDash USB Monitor.app"
```

Copy the built `.app` to Applications, open it once, then right-click the desktop
and choose **Edit Widgets**. Search for **ErgoDash** and add the medium-size
**ErgoDash Batteries** widget. It also works in Notification Center.
The app must remain running to read USB; closing its window keeps it running.
You can add it to Login Items in System Settings. It has no menu bar item.

Version 2.2 opens a draggable **344 × 82 point** desktop card by default. It
uses a system backdrop blur material that adapts to light/dark appearance.
The collector's **Show compact desktop widget** toggle controls its visibility.
It updates live and remembers its position. Native WidgetKit medium widgets
have a system-controlled outer height (164 points here), so the half-height
card is a companion-app window rather than a gallery widget.

Both views use one table row with two entries: **Left** and **Right**. Each
entry contains an SF Symbols **wifi** indicator followed by a battery icon
with the **battery percentage immediately beside it**. The gallery widget
uses SwiftUI's regular material. These are system materials; an exact visual
match to Apple's private Batteries widget has not been verified. Battery
icons use the standard percentage symbols and **battery.100percent.bolt**
when USB power is present. Low batteries appear red; available batteries green.

Signal help text contains both a percentage estimate and the measured RSSI,
such as `58% (−71 dBm)`, plus the update time. The display estimate is
`clamp(2 × (RSSI + 100), 0, 100)`; -100 dBm maps to 0%, -50 dBm to 100%.
It is not measured packet delivery or radio transmit power. A value closer to
zero is a stronger received signal. RSSI alone does not measure interference,
packet loss or typing latency. Battery help text includes voltage and USB status.
The same view in the collector supports native SwiftUI hover tooltips.
The installed native widget exposes this help text through accessibility;
the visible tooltip on hover still needs verification in the widget host.

The battery's bolt means **USB power detected on that half**. It does not mean that
the battery is actively charging: nice!nano v2 does not expose its charger
status to the MCU. Its physical charging LED remains the indicator of actual
charging. Voltage-derived battery percentages can rise prematurely while
charging. Accurate state of charge or charging/full status would require
additional sensing hardware.

For initial setup, flash matching normal firmware onto all three devices. Existing split
bonds can be retained. Physical left/right IDs are built into the halves.
If upgrading from the earlier USB monitor firmware, **reflash only both halves**
with firmware from commit `ded62ca` or later. This fixes missing battery values:
the nice!nano sensor requires `SENSOR_CHAN_GAUGE_VOLTAGE`, while the previous
code requested an unsupported generic voltage channel. The dongle protocol
is unchanged; its existing monitor firmware can remain installed. No settings
reset is needed. Allow about 40 seconds for the first battery readings.
The app supports one attached dongle; it selects the first matching interface.
This vendor HID interface does not listen to keystrokes. macOS may request
Input Monitoring permission when opening HID devices; allow it for this app
if access is denied, then quit and relaunch.

Battery voltage is sampled every 30 seconds, including while idle. The dongle
queries telemetry and RSSI every 5 seconds and sends USB snapshots every
second. It also supports feature reads so the app can get a snapshot after
the dongle is already connected. Disconnected, missing and stale readings show
`—` and disabled symbols. A sample older than 90 seconds is stale. The collector
hides its readings if it has not received a USB report for 10 seconds.

**WidgetKit controls refresh timing.** The collector writes fresh snapshots
every five seconds, requests widget reloads on battery/power/connection changes,
and otherwise requests updates every five minutes. macOS may throttle/coalesce
these requests, so the gallery widget is a snapshot and can lag behind the
live view in the collector. Click the widget to open that live view; use
**Refresh widget** to request a new timeline. Help text includes the timestamp
of the displayed snapshot. The compact desktop card updates live independently
of WidgetKit's refresh budget.

The build signs both bundles locally with an ad-hoc signature and verifies
the nested signature. It builds for the Mac's architecture. The widget runs
sandboxed and reads a JSON snapshot from its own Application Support directory.
The nonsandboxed collector writes that single telemetry file into the widget's
container (`~/Library/Containers/dev.andy.ergodash-usb-monitor.widget/Data/Library/Application Support/ErgoDashUSB/snapshot.json`).
This local build uses no shared App Group entitlement or developer certificate.
For App Store distribution, use a properly signed App Group instead.

Firmware polling adds some radio/ADC work, so battery runtime should be
checked on hardware. The peripheral sample task shares ZMK's low-priority
ADC workqueue to prevent overlapping battery conversions. The dongle uses a
separate workqueue for telemetry and HCI RSSI requests.

## Verification

```sh
clang -Wall -Wextra -Werror tests/protocol_test.c -o /tmp/ergodash-protocol-test
/tmp/ergodash-protocol-test
clang -Wall -Wextra -Werror -Itests/stubs tests/battery_sensor_test.c -o /tmp/ergodash-battery-test
/tmp/ergodash-battery-test
sh tools/ergodash-monitor/build.sh
open "tools/ergodash-monitor/build/ErgoDash USB Monitor.app" --args --demo
```

The C tests cover GATT packet validation, voltage conversion and the battery
driver's gauge-voltage channel contract, including sensor errors. The build
script also runs Swift decoder tests, including signed RSSI, zero versus
unknown battery levels, malformed data, disconnected halves and stale data.
`--demo` shows labelled sample data without opening USB devices.
Demo data is never written to the real widget. Snapshot tests cover encoding,
staleness, sample age and malformed data. For a standalone view render:

```sh
"tools/ergodash-monitor/build/ErgoDash USB Monitor.app/Contents/MacOS/ErgoDash USB Monitor" --render-preview /tmp/ergodash-widget.png
```

For local registration if the gallery does not discover a workspace build:

```sh
pluginkit -a "tools/ergodash-monitor/build/ErgoDash USB Monitor.app/Contents/PlugIns/ErgoDashWidget.appex"
```

Version 2.1 fixes the widget extension's startup entry point. The installed
extension has been verified to return its medium widget descriptor and archive
its gallery preview successfully through macOS's widget service. Registration
alone is not sufficient to validate extension startup. If updating from 2.0,
replace the app, reopen it, then close and reopen Edit Widgets. Keep the app in
Applications; moving an already registered copy can leave a stale launch path.

Hardware acceptance checks after flashing:

1. Keep a spare keyboard available and flash the matching normal firmware files
   (only both halves need updating for the `ded62ca` battery fix).
2. Confirm typing works through USB with Bluetooth on the Mac turned off.
3. Check that Left/Right show separate percentages and voltage help text within
   40 seconds in the live collector view. Add the widget and verify it reads
   the same snapshot. Confirm signal tooltips in the actual widget host.
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
