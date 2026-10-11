/* SPDX-License-Identifier: MIT */
#pragma once

#include <errno.h>
#include <stdint.h>
#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>

static inline int battery_sensor_read_mv(const struct device *battery, uint16_t *mv) {
    if (!device_is_ready(battery)) {
        return -ENODEV;
    }
    /* ZMK's battery voltage divider exposes the fuel-gauge channel. The
     * generic SENSOR_CHAN_VOLTAGE is rejected with -ENOTSUP by this driver. */
    int err = sensor_sample_fetch_chan(battery, SENSOR_CHAN_GAUGE_VOLTAGE);
    if (err) {
        return err;
    }
    struct sensor_value voltage;
    err = sensor_channel_get(battery, SENSOR_CHAN_GAUGE_VOLTAGE, &voltage);
    if (err) {
        return err;
    }
    int64_t reading = (int64_t)voltage.val1 * 1000 + voltage.val2 / 1000;
    if (reading < 0 || reading > UINT16_MAX) {
        return -ERANGE;
    }
    *mv = reading;
    return 0;
}
