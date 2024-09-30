#include "../../includes/packet.h"

interface Flooding {
    command void flood(uint8_t target, uint8_t* message, uint8_t len);
    command void handleFlood(pack* packet, uint8_t len);
}