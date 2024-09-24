#include "../../includes/packet.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    // uses interface Timer<TMilli> as discoveryTimer;
}

// uint16_t local_sequence_number = 0;

implementation {
    command void NeighborDiscovery.pass() {
        // discoveryTimer.start();
    }
    /*
    event void discoveryTimer.fired() {
        pack neighborDiscoveryPacket;
        uint8_t payload = "";
        // idk???
        uint16_t TTL = 20;
        makePack(&pack, TOS_NODE_ID, 0, TTL, PROTOCOL_NEIGHBOR_DISCOVERY, local_sequence_number, payload, 0);
        local_sequence_number += 1;
        // SimpleSend.send(pack, )
    }
    */
}


/*
void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
}
*/