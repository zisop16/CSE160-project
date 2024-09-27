#include "../../includes/packet.h"

interface Flooding {
    command void flood(uint16_t target, uint8_t* message, uint8_t len);
}