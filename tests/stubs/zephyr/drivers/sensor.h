#pragma once
#include <stdint.h>
#include <zephyr/device.h>
enum sensor_channel { SENSOR_CHAN_VOLTAGE, SENSOR_CHAN_GAUGE_VOLTAGE };
struct sensor_value { int32_t val1, val2; };
int sensor_sample_fetch_chan(const struct device *dev, enum sensor_channel channel);
int sensor_channel_get(const struct device *dev, enum sensor_channel channel, struct sensor_value *value);
