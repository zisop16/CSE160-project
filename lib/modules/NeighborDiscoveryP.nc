#include "../../includes/packet.h"
#include "Timer.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface Timer<TMilli> as discoveryTimer;
    uses interface SimpleSend as Sender;
}

implementation {
    // One second for timer I think??
    int second = 1024;
    int localSequenceNumber = 0;
    pack neighborDiscoveryPacket;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    event void discoveryTimer.fired() {
        uint8_t* payload = "";
        // idk???
        uint16_t TTL = 6;
        makePack(&neighborDiscoveryPacket, TOS_NODE_ID, 0, TTL, PROTOCOL_NEIGHBOR_DISCOVERY, localSequenceNumber, payload, 0);
        localSequenceNumber += 1;
        call Sender.send(neighborDiscoveryPacket, 0);
        // dbg(GENERAL_CHANNEL, "%d\n", TOS_NODE_ID);
    }
    
    command void NeighborDiscovery.start() {
        call discoveryTimer.startPeriodic(20 * second);
    }
}




