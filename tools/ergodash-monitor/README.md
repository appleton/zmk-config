# ErgoDash USB Monitor

A native **Notification Center widget** with a one-time setup app and a
background collector. Version 4 also includes the Mac and connected accessories
that macOS exposes to its Batteries widget. It has no separate desktop card
or menu bar item.
Build with Apple's developer tools on macOS 14+:

```sh
sh tools/ergodash-monitor/build.sh
```

GitHub Actions builds and tests the app on app-related pull requests. Every push
to `main` also publishes an Apple Silicon app ZIP and SHA-256 checksums on
[GitHub Releases](https://github.com/appleton/zmk-config/releases), numbered
`v1`, `v2`, `v3`, and so on. Releases are serialized and each number is reserved
as a draft before building. Retries reuse the same commit's version, recheck
publication state, and recover interrupted drafts without replacing a newer
release as Latest. Only main-branch allocation and publishing have write access;
pull request builds are read-only and cannot reserve or publish releases. The app
and extension both use that major version (`1.0`, `2.0`, etc.). The CI build
uses Xcode 27 on macOS 27 to match the private APIs verified here.

Release ZIPs preserve the nested ad-hoc signatures; Developer ID signing and
notarization are not configured. Local builds retain their default version;
`APP_VERSION` and `APP_BUILD_VERSION` can override it for a release build.

For the native discovery integration test, run outside a development sandbox:

```sh
clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework AppKit -framework IOKit \
  tools/ergodash-monitor/tests/SystemBatteriesTests.m -o /tmp/ergodash-native-battery-test
/tmp/ergodash-native-battery-test
```

It feeds Apple's parser twelve synthetic, previously unseen Bluetooth products
in memory, checks device discovery, actual charge values, native icon selection
and removal, and never registers fake devices with macOS or changes connections.

Copy `build/ErgoDash USB Monitor.app` from this directory to `/Applications`,
open it and choose **Install background service**. Open Notification Center,
choose **Edit Widgets**, search for **ErgoDash**, and add
**ErgoDash Batteries**. Choose **Large** for the native Batteries table size;
Medium is a compact table. Existing widgets receive the updated layout.
After installation, close or quit the setup app; collection continues.
Open it again to refresh the widget, reinstall or uninstall the service.

The collector is a per-user LaunchAgent at
`~/Library/LaunchAgents/dev.andy.ergodash-usb-monitor.collector.plist`.
It starts at login after boot and launchd restarts it if it exits. WidgetKit
and USB access run in the signed-in user's session, so a root boot daemon
would not be appropriate. The service runs the installed app with
`--background`, with no window, Dock icon or menu bar item. Leave the app in
Applications because the service and widget extension use that installed path.
For scripted setup, the executable also accepts `--install-service` and
`--uninstall-service`. Collector errors go to `~/Library/Logs/ErgoDashUSB/collector.log`.

The table uses the native Batteries row spacing, inset separators, white
labels and device icons. The keyboard halves occupy one additional row.
That row starts with a keyboard icon aligned to the device icon column and
the dongle's USB product name (“Ergodash” with the renamed firmware), read from its
HID device properties. No product name is hard-coded in the row; “Keyboard”
is the fallback until a name is available. The last reported name is retained
while the dongle is disconnected. Left and right readings follow in that order, separated
by a vertical divider, using the same battery gauge as the accessory rows.
Wi-Fi symbols are sized to the small battery indicators beside them.
All rows use one battery renderer. Charging symbols have their visible bounds
normalized to the same 21×9 point outline and common trailing inset as ordinary
gauges. Crowded keyboard rows adjust text and device-icon height without scaling
the whole row horizontally, keeping the right-hand battery aligned.
Large normally has six rows, Medium three; when more devices are connected,
rows become more compact instead of silently dropping devices.
Each keyboard entry reads from left to right:
**Wi-Fi icon → battery percentage → battery icon**. Version 3.1 requests the same **host blur background** as Apple's Batteries
widget through WidgetKit's internal `preferredBackgroundStyle(.blur)` API,
with a transparent content background and white text/icons. Drawing a glass
view inside the normal container does not remove the host's opaque white fill.
This does not change any global appearance settings.

`prepare-background-api.py` exposes that declaration in a build-local copy of
the installed SDK's Swift interface. The API and blur enum case are exported
by the installed WidgetKit framework and SDK linker stub, and imported by
Apple's Batteries extension. No installed SDK files are edited. This is a local
build using an internal API, not suitable for App Store distribution, and may
need adjustment after macOS updates. The current Mac has accepted the blur
preference and generated a fresh widget timeline.

Native sidebar widget dimensions are fixed by WidgetKit; a medium widget's
outer height cannot be halved.

## Mac and accessory batteries

`SystemBatteries.m` queries `IOPSCopyPowerSourcesByType(0)` for all current
power sources every five seconds. It passes that data to BatteryCenter's
`_orderedDevicesFromPowerSourcesBlob:powerSourcesList:` for Apple's names,
grouping, filtering and ordering, and BatteryCenterUI's
`batteryWidgetGlyphName:` for Apple's current device icons. There is no
device-name or product-ID whitelist, and no cached list of today's devices.
Connecting, disconnecting, changing names, changing charge or changing power
state updates the inventory and requests a WidgetKit reload.

`Image(_internalSystemName:)` renders the returned symbols, including Apple's
internal device symbols. Framework image assets are retained when provided.
Real MacBook, AirPods Pro and case glyphs have been read and rendered, and an
internal symbol unavailable through the public NSImage initializer has been
rendered too. This uses OS-supplied glyphs rather than bundled icon copies.

Devices need to report battery information to macOS, as they do for Apple's
widget. The collector does not scan, pair or connect Bluetooth devices.
Accessory charging and low-power states come from macOS; the USB-powered
keyboard bolt retains the hardware limitation described below. Accessory
batteries remain available when the keyboard dongle is disconnected.

Apple's complete rendering view reads the precise battery service, which
requires an Apple-only entitlement; an ad-hoc app cannot obtain that access.
This app uses the normal power-source data and native ordering/icon functions
instead. It requests no private battery entitlement and changes no system
framework. These private functions can change after a macOS update. If their
interfaces become unavailable, the collector falls back to actual OS battery
data with generic icons; exact icon matching then needs an adapter update.

The installed table has been compared beside Apple's Batteries widget in
Notification Center. Its existing instance was switched from Medium to Large
to match Apple's outer size and row spacing. Build 10 aligns label weight,
device icon bounds, battery inset and keyboard percentage spacing with that
comparison. The Apple widget has not been removed.

## Keyboard readings

Signal help contains an estimated percentage and measured RSSI in dBm.
The estimate is `clamp(2 × (RSSI + 100), 0, 100)`; -100 dBm
maps to 0%, -50 dBm to 100%. It does not measure packet loss, interference,
latency or radio transmit power. Battery help includes voltage and USB power.
The help text is archived for accessibility. Each signal icon is a plain Link
with help on the interactive element; visible hover tooltip behavior in the
Notification Center host remains unverified. Clicking a signal opens setup.

The battery bolt means **USB power detected on that half**. nice!nano v2 does
not expose the charger's status to the MCU, so active charging or charge
completion cannot be verified. The physical charge LED indicates active
charging. Battery percentages are voltage-derived estimates and may rise
prematurely while charging.

## Firmware

For initial USB monitor setup, flash matching normal firmware to all three
devices. Existing split bonds can be retained; physical left/right IDs are
built into the halves. If already using the earlier monitor firmware,
**reflash only both halves with `ded62ca` or later**. This fixes missing battery
values: the voltage-divider driver requires `SENSOR_CHAN_GAUGE_VOLTAGE`, while
the old code used an unsupported generic voltage channel. The existing dongle
monitor firmware remains compatible. No settings reset is needed.

Firmware `ac4db82` renames the dongle's USB product to “Ergodash”. For this name
change alone, reflash only the normal dongle HEX; the halves and stored bonds
do not need updating. The widget reads the USB product name on reconnect.

Allow about 40 seconds for battery readings after flashing. Battery voltage
is sampled every 30 seconds, including while idle and USB powered. Telemetry
and RSSI are queried every 5 seconds; the dongle sends USB reports every
second and also supports feature reads. Values older than 90 seconds are
stale. A USB snapshot older than 10 seconds is rejected when read.

The Mac only reads the dongle's USB vendor HID interface, with no Bluetooth
pairing with the Mac. It selects the first matching attached dongle and does
not listen to keystrokes. If macOS denies HID access, allow Input Monitoring
for this app, then reinstall/restart the service.

## Refresh and verification

The collector writes a fresh snapshot every five seconds and requests widget
reloads on battery/power/connection changes or every five minutes otherwise.
WidgetKit controls refresh timing and may throttle/coalesce requests: sidebar
readings are snapshots, not a live view. **Refresh widget** in setup requests a
new timeline. Battery help includes the displayed snapshot's timestamp.

The sandboxed extension reads a JSON file in its own Application Support
folder. The nonsandboxed collector writes only this telemetry file into
`~/Library/Containers/dev.andy.ergodash-usb-monitor.widget/Data/Library/Application Support/ErgoDashUSB/snapshot.json`.
This local ad-hoc build uses no App Group or developer certificate. App Store
distribution would need a properly signed shared App Group instead.

```sh
clang -Wall -Wextra -Werror tests/protocol_test.c -o /tmp/ergodash-protocol-test
/tmp/ergodash-protocol-test
clang -Wall -Wextra -Werror -Itests/stubs tests/battery_sensor_test.c -o /tmp/ergodash-battery-test
/tmp/ergodash-battery-test
sh tools/ergodash-monitor/build.sh
```

The build verifies nested code signatures and runs decoder/snapshot tests.
The C tests cover packet validation, voltage conversion and the actual battery
sensor channel contract. Version 2.1 fixed the extension startup entry point;
registration alone does not prove the extension can start. Version 3.0 removes
the separate desktop card and makes the app setup-only.

After replacing the app, stop the previous collector and widget extension,
register the updated installed extension, and reinstall the background service.
The installed widget has been verified to generate a new native timeline, and
the LaunchAgent to publish real USB telemetry and restart after termination.
Actual battery values still require the corrected firmware on both halves.
The installed widget was compared beside Apple's Batteries widget and the
user confirmed its final appearance. Charging and ordinary battery bounds
were also measured in offscreen normal, charging and crowded layouts; the
right edges match, and ordinary keyboard/accessory gauges at the same level
render identically.

Hardware checks after flashing: confirm separate percentages/voltage, connect
USB power to just one half and check its bolt, check updates while idle, move
halves to vary RSSI, power-cycle a half, and unplug/replug the dongle. No radio
connections beyond the existing split links are added, but runtime impact of
extra polling should be checked on hardware.

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
