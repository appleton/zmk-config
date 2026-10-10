#include <assert.h>
#include <stdio.h>
#include "../module/battery_sensor.h"

static struct sensor_value measured = {.val1 = 3, .val2 = 987000};
static int fetch_error, get_error, fetches, channel_reads;

/* Match the actual ZMK battery voltage-divider driver's channel contract. */
int sensor_sample_fetch_chan(const struct device *dev, enum sensor_channel channel) {
    (void)dev;
    fetches++;
    return channel == SENSOR_CHAN_GAUGE_VOLTAGE ? fetch_error : -ENOTSUP;
}

int sensor_channel_get(const struct device *dev, enum sensor_channel channel, struct sensor_value *value) {
    (void)dev;
    channel_reads++;
    if (channel != SENSOR_CHAN_GAUGE_VOLTAGE) { return -ENOTSUP; }
    *value = measured;
    return get_error;
}

int main(void) {
    struct device battery = {.ready = true};
    uint16_t mv = 0;
    assert(battery_sensor_read_mv(&battery, &mv) == 0 && mv == 3987);
    battery.ready = false;
    assert(battery_sensor_read_mv(&battery, &mv) == -ENODEV && fetches == 1);
    battery.ready = true;
    fetch_error = -EIO;
    assert(battery_sensor_read_mv(&battery, &mv) == -EIO && channel_reads == 1);
    fetch_error = 0;
    get_error = -EIO;
    assert(battery_sensor_read_mv(&battery, &mv) == -EIO);
    get_error = 0;
    measured = (struct sensor_value){.val1 = -1};
    assert(battery_sensor_read_mv(&battery, &mv) == -ERANGE);
    measured = (struct sensor_value){.val1 = INT32_MAX};
    assert(battery_sensor_read_mv(&battery, &mv) == -ERANGE);
    measured = (struct sensor_value){.val1 = 4, .val2 = 200000};
    assert(battery_sensor_read_mv(&battery, &mv) == 0 && mv == 4200);
    puts("Battery sensor tests passed");
}
