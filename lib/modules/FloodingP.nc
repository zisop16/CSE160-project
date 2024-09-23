#include "../../includes/packet.h"

module FloodingP {
    provides interface Flooding;
    uses interface Timer<TMilli> as floodingTimer;
}

implementation {
    command void Flooding.pass() {

    }
}

event void floodingTimer.fired() {
    // pack 
}
