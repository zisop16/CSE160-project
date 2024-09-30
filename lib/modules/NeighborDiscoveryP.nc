#include "../../includes/packet.h"
#include "../../includes/constants.h"
#include "Timer.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface Timer<TMilli> as discoveryTimer;
    uses interface SimpleSend as Sender;
}

implementation {
    int localSequenceNumber = 0;
    // Store 19 floats for neighbor response statistics
    float neighborResponseStatistics[NUM_NODES];
    // Alpha for exponential weighting
    const float alpha = .2;


    pack neighborDiscoveryPacket;
    pack neighborReplyPacket;

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
            neighborResponseStatistics[i] *= 1 - alpha;
        }
    }
    
    command float* NeighborDiscovery.statistics() {
        return neighborResponseStatistics;
    }
    
    command void NeighborDiscovery.start() {
        call discoveryTimer.startPeriodic(30 * second);
    }
    command void NeighborDiscovery.reply(pack* neighborPacket) {
        uint8_t* payload = "";
        uint16_t TTL = 1;
        makePack(&neighborReplyPacket, TOS_NODE_ID, neighborPacket->src, TTL, PROTOCOL_NEIGHBOR_REPLY, neighborPacket->seq, payload, 0);
        call Sender.send(neighborReplyPacket, neighborPacket->src);
    }
    command void NeighborDiscovery.readReply(pack* confirmationPacket) {
        int sequenceNum = confirmationPacket->seq;
        int neighborID;
        
        // If this is a reply to an older sequence number, we throw it out
        if (sequenceNum != localSequenceNumber) {
            return;
        }
        neighborID = confirmationPacket->src;
        neighborResponseStatistics[neighborID - 1] += alpha;
        // dbg(NEIGHBOR_CHANNEL, "Current statistics on neighbor %d: %d\n", neighborID, currentStats);
    }
    command void NeighborDiscovery.printNeighbors() {
        int i;
        float stat;
        for (i = 0; i < NUM_NODES; i++) {
            stat = neighborResponseStatistics[i];
            if (stat >= .5) {
                dbg(NEIGHBOR_CHANNEL, "I am neighbors with node: %d at confidence: %f\n", i + 1, stat);
            }
        }
    }
}




