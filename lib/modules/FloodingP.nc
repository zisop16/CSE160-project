#include "../../includes/packet.h"

module FloodingP {
    provides interface Flooding;
}

implementation {
    command void Flooding.flood(uint16_t target, uint8_t* message, uint8_t len) {
        
    }
}


