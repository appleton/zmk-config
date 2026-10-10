/* SPDX-License-Identifier: MIT */
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <hal/nrf_power.h>
#include <string.h>
#include <zmk/workqueue.h>

#include "protocol.h"

static const struct device *const battery = DEVICE_DT_GET(DT_CHOSEN(zmk_battery));
static struct bt_uuid_128 service_uuid = BT_UUID_INIT_128(ERGODASH_SERVICE_UUID);
static struct bt_uuid_128 value_uuid = BT_UUID_INIT_128(ERGODASH_VALUE_UUID);
static struct k_spinlock snapshot_lock;
static uint8_t snapshot[BATTERY_GATT_SIZE] = {
    BATTERY_VERSION, CONFIG_ERGODASH_BATTERY_SIDE, 0, BATTERY_UNKNOWN,
};
static int64_t sampled_at;

static void sample_battery(struct k_work *work) {
    struct sensor_value voltage;
    uint16_t mv = 0;
    bool valid = device_is_ready(battery) &&
                 sensor_sample_fetch_chan(battery, SENSOR_CHAN_VOLTAGE) == 0 &&
                 sensor_channel_get(battery, SENSOR_CHAN_VOLTAGE, &voltage) == 0;
    if (valid) {
        int32_t reading = voltage.val1 * 1000 + voltage.val2 / 1000;
        valid = reading >= 0 && reading <= UINT16_MAX;
        mv = valid ? reading : 0;
    }
    k_spinlock_key_t key = k_spin_lock(&snapshot_lock);
    snapshot[2] = valid ? BATTERY_VALID : 0;
    snapshot[3] = valid ? battery_percent(mv) : BATTERY_UNKNOWN;
    battery_put_u16(mv, &snapshot[4]);
    sampled_at = k_uptime_get();
    k_spin_unlock(&snapshot_lock, key);
    /* Use ZMK's ADC workqueue so its own battery sampling cannot overlap ours.
     * Keep sampling while idle/charging, when stock battery updates may stop. */
    k_work_reschedule_for_queue(zmk_workqueue_lowprio_work_q(),
                               k_work_delayable_from_work(work), K_SECONDS(30));
}

K_WORK_DELAYABLE_DEFINE(sample_work, sample_battery);

static ssize_t read_battery(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf,
                            uint16_t len, uint16_t offset) {
    uint8_t packet[BATTERY_GATT_SIZE];
    k_spinlock_key_t key = k_spin_lock(&snapshot_lock);
    memcpy(packet, snapshot, sizeof(packet));
    uint16_t age = MIN((k_uptime_get() - sampled_at) / 1000, UINT16_MAX);
    k_spin_unlock(&snapshot_lock, key);
    /* VBUS detection also works with a wall charger and without a USB stack.
     * The nice!nano charger STAT pin is LED-only: this is NOT charging state. */
    if (nrf_power_usbregstatus_vbusdet_get(NRF_POWER)) {
        packet[2] |= BATTERY_USB_POWERED;
    }
    battery_put_u16(age, &packet[6]);
    return bt_gatt_attr_read(conn, attr, buf, len, offset, packet, sizeof(packet));
}

BT_GATT_SERVICE_DEFINE(ergodash_battery, BT_GATT_PRIMARY_SERVICE(&service_uuid),
                       BT_GATT_CHARACTERISTIC(&value_uuid.uuid, BT_GATT_CHRC_READ,
                                              BT_GATT_PERM_READ_ENCRYPT, read_battery, NULL, NULL));

static int battery_init(void) {
    return k_work_schedule_for_queue(zmk_workqueue_lowprio_work_q(), &sample_work, K_NO_WAIT) < 0
               ? -EIO
               : 0;
}

SYS_INIT(battery_init, APPLICATION, 90);
