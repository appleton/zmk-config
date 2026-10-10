# Keyboard layouts

[Edit here](https://nickcoutsos.github.io/keymap-editor/)

Firmware builds track ZMK's development branch, `main`, in both
`config/west.yml` and `.github/workflows/build.yml`. Keep these references in sync
when changing versions.

Both ErgoDash halves use nice!nano v2 controllers (`nice_nano@2.0.0//zmk`).
The upstream board definition supplies battery sensing; no local battery
overlays are needed. See the [Zephyr 4.1 migration notes](https://zmk.dev/blog/2025/12/09/zephyr-4-1)
for the board naming changes.

## Dongle configuration

The Raytac MDBT50Q-CX-40 USB-C dongle is the central and connects to the
computer over USB. Both nice!nano v2 halves are
Bluetooth peripherals that connect to it. The keymap is unchanged and all three
parts use +8 dBm transmit power. The keyboard requires the dongle in this mode.

Following [Raytac's instructions](https://www.raytac.com/news/ins.php?index_id=175),
the dongle builds use the Nordic base target `nrf52840dongle/nrf52840/zmk` with
both DC/DC power stages disabled. In Zephyr 4.1 this is configured by
`config/nrf52840dongle.overlay`: `reg0` is disabled and `reg1` uses LDO mode.
The overlay applies to both the normal dongle and its settings-reset firmware.
The dedicated Raytac board target is not present in the Zephyr version used by
this ZMK revision. The Nordic base supplies compatible USB, bootloader flash
layout, 3.0 V initialization, button (P1.06), and LED (P0.06/P0.08) definitions.

The local dongle shield copies the matrix transform from upstream ErgoDash;
keep these in sync if the upstream layout changes. See ZMK's
[dongle guide](https://zmk.dev/docs/hardware-integration/dongle).

Push the changes to GitHub, then download the `firmware` artifact from the
successful **Build ZMK firmware** Actions run. It contains:

| File | Device / purpose |
| --- | --- |
| `ergodash-dongle-raytac-mdbt50q-cx.hex` | Raytac MDBT50Q-CX-40 dongle |
| `ergodash-left-peripheral-nice-nano-v2.uf2` | Left half |
| `ergodash-right-peripheral-nice-nano-v2.uf2` | Right half |
| `settings-reset-nice-nano-v2.uf2` | Clear settings on either keyboard half |
| `settings-reset-raytac-mdbt50q-cx.hex` | Clear settings on the Raytac dongle |

### First flash or switching between two-part and dongle modes

1. Keep a spare keyboard available during flashing. Turn off both halves.
2. Flash the matching settings-reset firmware to **each of the three devices**
   and let it run for several seconds. This clears stored Bluetooth bonds and
   other saved ZMK settings; just flashing the normal firmware does not.
3. Put each device back into its bootloader and flash its matching normal
   firmware. Switch the halves off after flashing until all three are ready.
4. Plug the dongle into USB and turn both halves on nearby so they can pair.
   No pairing in the computer's Bluetooth settings is needed for this setup.

For nice!nano v2, enter the UF2 bootloader (normally by resetting twice quickly)
and copy the `.uf2` onto its mounted drive.

The Raytac has one externally accessible button. Leave its case closed. Unplug
it, hold the button, plug it back in, and keep holding for about one second
until the LED lights; then release it. The LED keeps flashing in DFU mode.
In **nRF Connect for Desktop → Programmer**, select **Open DFU Bootloader**,
add only `settings-reset-raytac-mdbt50q-cx.hex`, and click **Write**. Let the
reset firmware run for at least five seconds. Repeat the unplug/hold/plug
sequence, clear the previous file from Programmer, and write only
`ergodash-dongle-raytac-mdbt50q-cx.hex`. No separate SoftDevice or bootloader
image is needed for these ZMK builds. See [Raytac's DFU instructions](https://www.raytac.com/news/ins.php?index_id=175).

### USB battery and signal monitor

The firmware includes a separate USB HID interface for
[ErgoDash USB Monitor](tools/ergodash-monitor/README.md), a small native macOS
menu bar app. The Mac reads all telemetry over the dongle's USB connection;
no Bluetooth pairing with the Mac is required.

It shows each half's estimated battery percentage, battery voltage, USB power
status and signal strength (RSSI) received at the dongle. Percentages continue
updating while idle and charging. Left/right identities are set in `build.yaml`,
so they do not depend on pairing order. Both halves and the dongle must run
the matching monitor firmware. Flash the three **normal** firmware files;
settings-reset firmware is not needed for this update.

The nice!nano v2 charger's status output is connected to its charge LED, not
to the processor. The app therefore says **USB powered**, rather than claiming
that the battery is charging or full. The charge LED indicates actual charging.
Battery percentages are voltage-based estimates and can read high during
charging; a 100% estimate does not establish that charging has finished.
See the [nice!nano schematic](https://nicekeyboards.com/docs/nice-nano/pinout-schematic/).

Build and run the app:

```sh
sh tools/ergodash-monitor/build.sh
open "tools/ergodash-monitor/build/ErgoDash USB Monitor.app"
```

### Restore the original two-part setup

The previous +8 dBm configuration remains on branch `aa/bluetooth-tx-power`,
commit `029e08ebfadbc70ec9750495b73250360720c8a0`. Its exact compiled firmware
is in [Actions run 36250673127](https://github.com/appleton/zmk-config/actions/runs/36250673127),
and was also saved separately on the Desktop before making these changes.

Unplug the dongle. Flash `settings-reset-nice-nano-v2.uf2` to both halves and
let it run. Then flash the original left/right firmware to the matching halves,
restart both together, and forget/re-pair the keyboard in the computer's
Bluetooth settings. The left half is once again the central and can also
connect to the computer over USB.
