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
    // I have no clue if the number of nodes is guaranteed to be 19. I can change this system later if I need to I guess
    const int NUM_NODES = 19;
    // Store 19 ints each with 16 bits for neighbor response statistics
    // If (neighborResponseStatistics[i] & (1 << n) != 0) then neighbor i responded to the n'th most recent neighbor discovery request
    // After 16 neighbor discovery requests have been sent, the least recent data will be kicked out
    uint16_t neighborResponseStatistics[19];


    pack neighborDiscoveryPacket;
    pack neighborReplyPacket;

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
        uint16_t TTL = 1;
        int i;
        localSequenceNumber += 1;
        makePack(&neighborDiscoveryPacket, TOS_NODE_ID, AM_BROADCAST_ADDR, TTL, PROTOCOL_NEIGHBOR_DISCOVERY, localSequenceNumber, payload, 0);
        call Sender.send(neighborDiscoveryPacket, AM_BROADCAST_ADDR);
        for (i = 0; i < NUM_NODES; i++) {
            // Left shift all neighbor response statistics so that our next bit will be from this set of neighborResponses
            neighborResponseStatistics[i] <<= 1;
        }
    }
    
    command void NeighborDiscovery.start() {
        call discoveryTimer.startPeriodic(40 * second);
    }
    command void NeighborDiscovery.reply(pack* neighborPacket) {
        uint8_t payload = "";
        uint16_t TTL = 1;
        makePack(&neighborReplyPacket, TOS_NODE_ID, neighborPacket->src, TTL, PROTOCOL_NEIGHBOR_REPLY, neighborPacket->seq, payload, 0);
        call Sender.send(neighborReplyPacket, neighborPacket->src);
    }
    command void NeighborDiscovery.readReply(pack* confirmationPacket) {
        int sequenceNum = confirmationPacket->seq;
        int neighborID;
        uint16_t currentStats;
        // If this is a reply to an older sequence number, we throw it out
        if (sequenceNum != localSequenceNumber) {
            return;
        }
        neighborID = confirmationPacket->src;
        currentStats = neighborResponseStatistics[neighborID - 1];
        // Set the rightmost bit to 1
        currentStats = currentStats | 1;
        neighborResponseStatistics[neighborID - 1] = currentStats;
        dbg(NEIGHBOR_CHANNEL, "Current statistics on neighbor %d: %d\n", neighborID, currentStats);
    } 
}




