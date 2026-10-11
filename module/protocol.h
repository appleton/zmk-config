/* SPDX-License-Identifier: MIT */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Private GATT characteristic on the existing half-to-dongle BLE link. */
#define ERGODASH_SERVICE_UUID BT_UUID_128_ENCODE(0x079a1700, 0x697a, 0x4ba7, 0xb9d5, 0xb4d2bf4e7f90)
#define ERGODASH_VALUE_UUID BT_UUID_128_ENCODE(0x079a1701, 0x697a, 0x4ba7, 0xb9d5, 0xb4d2bf4e7f90)

#define BATTERY_VERSION 1
#define BATTERY_SIDES 2
#define BATTERY_VALID 0x01
#define BATTERY_USB_POWERED 0x02
#define BATTERY_CONNECTED 0x04
#define BATTERY_RSSI_VALID 0x08
#define BATTERY_UNKNOWN 0xff
#define BATTERY_GATT_SIZE 8
#define BATTERY_HID_ID 1
#define BATTERY_HID_SIDE_SIZE 9
#define BATTERY_HID_SIZE (2 + BATTERY_SIDES * BATTERY_HID_SIDE_SIZE)
#define BATTERY_STALE_SECONDS 90

static inline uint16_t battery_u16(const uint8_t *p) {
    return p[0] | ((uint16_t)p[1] << 8);
}

static inline void battery_put_u16(uint16_t value, uint8_t *p) {
    p[0] = value & 0xff;
    p[1] = value >> 8;
}

static inline bool battery_packet_valid(const uint8_t *p, size_t len) {
    return len == BATTERY_GATT_SIZE && p[0] == BATTERY_VERSION && p[1] < BATTERY_SIDES &&
           (p[2] & ~(BATTERY_VALID | BATTERY_USB_POWERED)) == 0 &&
           ((p[2] & BATTERY_VALID) ? p[3] <= 100 : p[3] == BATTERY_UNKNOWN);
}

/* Matches ZMK's voltage-based estimate; this is not a fuel gauge. */
static inline uint8_t battery_percent(uint16_t mv) {
    if (mv >= 4200) {
        return 100;
    }
    if (mv <= 3450) {
        return 0;
    }
    return (uint32_t)mv * 2 / 15 - 459;
}
