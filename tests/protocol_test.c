#include <assert.h>
#include <stdio.h>
#include "../module/protocol.h"

int main(void) {
    uint8_t packet[] = {1, 0, BATTERY_VALID | BATTERY_USB_POWERED, 84, 0xca, 0x0f, 12, 0};
    assert(battery_packet_valid(packet, sizeof(packet)));
    assert(battery_u16(&packet[4]) == 4042);
    packet[1] = 1;
    assert(battery_packet_valid(packet, sizeof(packet))); /* Explicit right ID */
    packet[1] = 2;
    assert(!battery_packet_valid(packet, sizeof(packet)));
    packet[1] = 0;
    assert(!battery_packet_valid(packet, sizeof(packet) - 1));
    packet[0] = 2;
    assert(!battery_packet_valid(packet, sizeof(packet)));
    packet[0] = 1; packet[3] = 101;
    assert(!battery_packet_valid(packet, sizeof(packet)));
    packet[3] = 0;
    assert(battery_packet_valid(packet, sizeof(packet))); /* Real empty battery */
    packet[2] = 0; packet[3] = BATTERY_UNKNOWN;
    assert(battery_packet_valid(packet, sizeof(packet)));
    packet[2] = BATTERY_CONNECTED;
    assert(!battery_packet_valid(packet, sizeof(packet))); /* Central-only flag */
    battery_put_u16(65535, &packet[6]);
    assert(battery_u16(&packet[6]) == 65535);
    assert(battery_percent(0) == 0 && battery_percent(3450) == 0);
    assert(battery_percent(4200) == 100 && battery_percent(4500) == 100);
    for (int mv = 3451; mv < 4200; mv++) {
        assert(battery_percent(mv) <= 100);
        assert(battery_percent(mv) >= battery_percent(mv - 1));
    }
    puts("Firmware protocol tests passed");
}
