# Keyboard layouts

[Edit here](https://nickcoutsos.github.io/keymap-editor/)

Firmware builds track ZMK's development branch, `main`, in both
`config/west.yml` and `.github/workflows/build.yml`. Keep these references in sync
when changing versions. The latest stable release is still v0.3.0 as of
2026-09-22.

Both ErgoDash halves use nice!nano v2 controllers (`nice_nano@2.0.0//zmk`).
The upstream board definition supplies battery sensing; no local battery
overlays are needed. See the [Zephyr 4.1 migration notes](https://zmk.dev/blog/2025/12/09/zephyr-4-1)
for the board naming changes.

Push the changes to GitHub to build the firmware, then download the `firmware`
artifact from the successful **Build ZMK firmware** Actions run. Flash the
matching `.uf2` file to each half when upgrading.
