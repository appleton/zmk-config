/* SPDX-License-Identifier: MIT */
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/device.h>
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/usb/class/usb_hid.h>
#include <zmk/usb.h>

#include "protocol.h"

static struct bt_uuid_128 value_uuid = BT_UUID_INIT_128(ERGODASH_VALUE_UUID);
static const struct device *hid;
static struct k_spinlock state_lock;

struct half_state {
    uint8_t flags;
    uint8_t percent;
    uint16_t mv;
    int64_t sampled_at;
    int64_t received_at;
    struct bt_conn *owner; /* Borrowed; disconnect callback clears it. */
    int8_t rssi;
    int64_t rssi_at;
};

static struct half_state halves[BATTERY_SIDES];

struct read_context {
    struct bt_gatt_read_params params;
    struct bt_conn *conn; /* Owned while the asynchronous request is pending. */
    int8_t rssi;
    int64_t rssi_at;
};
static struct read_context reads[CONFIG_BT_MAX_CONN];
static struct k_work_q telemetry_queue;
K_THREAD_STACK_DEFINE(telemetry_stack, 2048);

/* A vendor interface distinct from the keyboard, readable without a driver. */
static const uint8_t descriptor[] = {
    0x06, 0x60, 0xff, /* Usage page 0xff60 */
    0x09, 0x61,       /* Usage 0x61 */
    0xa1, 0x01,
    0x85, BATTERY_HID_ID,
    0x15, 0x00,
    0x26, 0xff, 0x00,
    0x75, 0x08,
    0x95, BATTERY_HID_SIZE - 1,
    0x09, 0x62,
    0x81, 0x02,       /* Input snapshot */
    0x09, 0x62,
    0xb1, 0x02,       /* Feature snapshot for apps opened after connection */
    0xc0,
};

static void make_report(uint8_t *report) {
    report[0] = BATTERY_HID_ID;
    report[1] = BATTERY_VERSION;
    int64_t now = k_uptime_get();
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    for (int side = 0; side < BATTERY_SIDES; side++) {
        struct half_state *half = &halves[side];
        uint8_t *out = &report[2 + side * BATTERY_HID_SIDE_SIZE];
        out[0] = half->flags;
        if (half->owner && now - half->received_at <= BATTERY_STALE_SECONDS * 1000) {
            out[0] |= BATTERY_CONNECTED;
        }
        out[1] = (half->flags & BATTERY_VALID) ? half->percent : BATTERY_UNKNOWN;
        battery_put_u16(half->mv, &out[2]);
        uint16_t age = (half->flags & BATTERY_VALID)
                           ? MIN((now - half->sampled_at) / 1000, UINT16_MAX)
                           : UINT16_MAX;
        battery_put_u16(age, &out[4]);
        out[6] = half->rssi;
        battery_put_u16((half->flags & BATTERY_RSSI_VALID)
                            ? MIN((now - half->rssi_at) / 1000, UINT16_MAX)
                            : UINT16_MAX,
                        &out[7]);
    }
    k_spin_unlock(&state_lock, key);
}

static int get_report(const struct device *dev, struct usb_setup_packet *setup, int32_t *len,
                      uint8_t **data) {
    static uint8_t report[BATTERY_HID_SIZE];
    if ((setup->wValue & 0xff) != BATTERY_HID_ID || (setup->wValue >> 8) != 3) {
        return -ENOTSUP;
    }
    make_report(report);
    *data = report;
    *len = MIN(*len, sizeof(report));
    return 0;
}

static const struct hid_ops hid_ops = {.get_report = get_report};

static void finish_read(struct read_context *ctx) {
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    struct bt_conn *conn = ctx->conn;
    ctx->conn = NULL;
    k_spin_unlock(&state_lock, key);
    if (conn) {
        bt_conn_unref(conn);
    }
}

static uint8_t battery_read(struct bt_conn *conn, uint8_t err, struct bt_gatt_read_params *params,
                            const void *data, uint16_t len) {
    struct read_context *ctx = CONTAINER_OF(params, struct read_context, params);
    const uint8_t *packet = data;
    struct bt_conn_info info;
    if (!err && packet && battery_packet_valid(packet, len) &&
        bt_conn_get_info(conn, &info) == 0 && info.state == BT_CONN_STATE_CONNECTED) {
        int64_t now = k_uptime_get();
        k_spinlock_key_t key = k_spin_lock(&state_lock);
        struct half_state *half = &halves[packet[1]];
        half->flags = packet[2];
        half->percent = packet[3];
        half->mv = battery_u16(&packet[4]);
        half->sampled_at = now - (int64_t)battery_u16(&packet[6]) * 1000;
        half->received_at = now;
        half->owner = conn;
        if (ctx->rssi != 127) {
            half->rssi = ctx->rssi;
            half->rssi_at = ctx->rssi_at;
            half->flags |= BATTERY_RSSI_VALID;
        }
        k_spin_unlock(&state_lock, key);
    }
    finish_read(ctx);
    return BT_GATT_ITER_STOP;
}

static int8_t read_rssi(struct bt_conn *conn) {
    uint16_t handle;
    if (bt_hci_get_conn_handle(conn, &handle) != 0) {
        return 127;
    }
    struct net_buf *cmd = bt_hci_cmd_create(BT_HCI_OP_READ_RSSI, sizeof(struct bt_hci_cp_read_rssi));
    if (!cmd) {
        return 127;
    }
    struct bt_hci_cp_read_rssi *cp = net_buf_add(cmd, sizeof(*cp));
    cp->handle = sys_cpu_to_le16(handle);
    struct net_buf *response = NULL;
    int err = bt_hci_cmd_send_sync(BT_HCI_OP_READ_RSSI, cmd, &response);
    int8_t rssi = 127;
    if (!err && response && response->len >= sizeof(struct bt_hci_rp_read_rssi)) {
        struct bt_hci_rp_read_rssi *rp = (void *)response->data;
        if (!rp->status) {
            rssi = rp->rssi;
        }
    }
    if (response) {
        net_buf_unref(response);
    }
    return rssi;
}

static void poll_connection(struct bt_conn *conn, void *user_data) {
    struct bt_conn_info info;
    if (bt_conn_get_info(conn, &info) != 0 || info.state != BT_CONN_STATE_CONNECTED ||
        info.role != BT_CONN_ROLE_CENTRAL || info.security.level < BT_SECURITY_L2) {
        return;
    }
    struct read_context *ctx = &reads[bt_conn_index(conn)];
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    if (ctx->conn) {
        k_spin_unlock(&state_lock, key);
        return;
    }
    ctx->conn = bt_conn_ref(conn);
    k_spin_unlock(&state_lock, key);
    /* This runs on a separate workqueue: the synchronous HCI command cannot
     * block the keyboard's normal event/work queues. 127 means unavailable. */
    ctx->rssi = read_rssi(conn);
    ctx->rssi_at = k_uptime_get();
    ctx->params = (struct bt_gatt_read_params){
        .func = battery_read,
        .handle_count = 0,
        .by_uuid = {.start_handle = 1, .end_handle = 0xffff, .uuid = &value_uuid.uuid},
    };
    if (bt_gatt_read(conn, &ctx->params) != 0) {
        finish_read(ctx);
    }
}

static void disconnected(struct bt_conn *conn, uint8_t reason) {
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    for (int side = 0; side < BATTERY_SIDES; side++) {
        if (halves[side].owner == conn) {
            halves[side].owner = NULL;
        }
    }
    k_spin_unlock(&state_lock, key);
    /* Zephyr completes/cancels pending GATT reads on disconnect. Their
     * callbacks release references; don't reuse live read params here. */
}

BT_CONN_CB_DEFINE(battery_connections) = {.disconnected = disconnected};

static void poll_work_handler(struct k_work *work) {
    bt_conn_foreach(BT_CONN_TYPE_LE, poll_connection, NULL);
    k_work_reschedule_for_queue(&telemetry_queue, k_work_delayable_from_work(work), K_SECONDS(5));
}

static void report_work_handler(struct k_work *work) {
    if (hid && zmk_usb_is_hid_ready()) {
        uint8_t report[BATTERY_HID_SIZE];
        make_report(report);
        /* Busy endpoints retry on the next tick; never delay keyboard input. */
        hid_int_ep_write(hid, report, sizeof(report), NULL);
    }
    k_work_reschedule_for_queue(&telemetry_queue, k_work_delayable_from_work(work), K_SECONDS(1));
}

K_WORK_DELAYABLE_DEFINE(poll_work, poll_work_handler);
K_WORK_DELAYABLE_DEFINE(report_work, report_work_handler);

static int battery_init(void) {
    hid = device_get_binding("HID_1");
    if (!hid) {
        return -ENODEV;
    }
    usb_hid_register_device(hid, descriptor, sizeof(descriptor), &hid_ops);
    int err = usb_hid_init(hid);
    if (err) {
        return err;
    }
    k_work_queue_start(&telemetry_queue, telemetry_stack, K_THREAD_STACK_SIZEOF(telemetry_stack),
                       10, NULL);
    k_work_schedule_for_queue(&telemetry_queue, &poll_work, K_SECONDS(5));
    k_work_schedule_for_queue(&telemetry_queue, &report_work, K_SECONDS(1));
    return 0;
}

/* Both HID interfaces must initialize before ZMK enables USB at priority 96. */
SYS_INIT(battery_init, APPLICATION, CONFIG_ZMK_USB_HID_INIT_PRIORITY);
