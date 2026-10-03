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

The Nordic nRF52840 Dongle (PCA10059, `nrf52840dongle/nrf52840/zmk`) is the
central and connects to the computer over USB. Both nice!nano v2 halves are
Bluetooth peripherals that connect to it. The keymap is unchanged and all three
parts use +8 dBm transmit power. The keyboard requires the dongle in this mode.

The local dongle shield copies the matrix transform from upstream ErgoDash;
keep these in sync if the upstream layout changes. See ZMK's
[dongle guide](https://zmk.dev/docs/hardware-integration/dongle).

Push the changes to GitHub, then download the `firmware` artifact from the
successful **Build ZMK firmware** Actions run. It contains:

| File | Device / purpose |
| --- | --- |
| `ergodash-dongle-nrf52840.hex` | Nordic PCA10059 dongle |
| `ergodash-left-peripheral-nice-nano-v2.uf2` | Left half |
| `ergodash-right-peripheral-nice-nano-v2.uf2` | Right half |
| `settings-reset-nice-nano-v2.uf2` | Clear settings on either keyboard half |
| `settings-reset-nrf52840-dongle.hex` | Clear settings on the dongle |

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
and copy the `.uf2` onto its mounted drive. For a PCA10059 with the stock Nordic
bootloader, press its reset button to enter DFU mode (pulsing red LED) and use
**nRF Connect for Desktop → Programmer** to write the `.hex`; it is not a UF2
drive. See the [Nordic flashing instructions](https://academy.nordicsemi.com/flash-instructions-for-nrf52840-dongle/).

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
