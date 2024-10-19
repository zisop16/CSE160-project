#include "../../includes/packet.h"
#include "../../includes/constants.h"
#include "Timer.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface Timer<TMilli> as discoveryTimer;
    uses interface SimpleSend as Sender;
}

implementation {
    uint16_t localSequenceNumber = 0;
    // Store 19 floats for neighbor response statistics
    float neighborResponseStatistics[NUM_NODES];
    float neighborResponseStatisticsNext[NUM_NODES];
    const float NEIGHBOR_THRESHOLD = .5;

    // Neighbors is a bitmask for bools indicating whether each node is a neighbor
    // ((NUM_NODES - 1) / 8) + 1 == ceil(NUM_NODES / 8.)
    // If we have 9 nodes, we use 2 bytes
    // If we have 8 nodes, we use 1 byte
    // If we have 40 nodes, we use 5 bytes
    uint8_t neighbors[neighborBytes];
    // Alpha for exponential weighting
    const float alpha = .2;


    pack neighborDiscoveryPacket;
    pack neighborReplyPacket;

    void calculateNeighbors() {
        uint8_t i;
        uint8_t byteIndex = 0;
        uint8_t bitIndex;
        uint8_t currValue = 0;
        int currIsNeighbor;
        for (i = 0; i < NUM_NODES; i++) {
            if (byteIndex != i / 8) {
                neighbors[byteIndex] = currValue;
                currValue = 0;
            }
            byteIndex = i / 8;
            bitIndex = i % 8;
            neighborResponseStatistics[i] = neighborResponseStatisticsNext[i];
            currIsNeighbor = neighborResponseStatistics[i] > NEIGHBOR_THRESHOLD;
            currValue = currValue + (currIsNeighbor << bitIndex);
        }
    }
    uint8_t _isNeighbor(uint8_t nodeID) {
        uint8_t byteIndex;
        uint8_t bitIndex;
        // Node with ID 1 == index 0
        nodeID -= 1;
        byteIndex = nodeID / 8;
        bitIndex = nodeID % 8;
        return (neighbors[byteIndex] >> bitIndex) & 1;
    }

    event void discoveryTimer.fired() {
        uint8_t* payload = "";
        // idk???
        uint16_t TTL = 1;
        int i;
        localSequenceNumber += 1;
        makePack(&neighborDiscoveryPacket, TOS_NODE_ID, AM_BROADCAST_ADDR, TTL, PROTOCOL_NEIGHBOR_DISCOVERY, localSequenceNumber, payload, 0);
        call Sender.send(neighborDiscoveryPacket, AM_BROADCAST_ADDR);
        
        calculateNeighbors();
        for (i = 0; i < NUM_NODES; i++) {
            neighborResponseStatisticsNext[i] = neighborResponseStatistics[i] * (1 - alpha);
        }
    }
    command uint8_t NeighborDiscovery.isNeighbor(uint8_t nodeID) {
        return _isNeighbor(nodeID);
    }
    
    command uint8_t* NeighborDiscovery.getNeighbors() {
        return neighbors;
    }
    
    command void NeighborDiscovery.start() {
        call discoveryTimer.startPeriodic(15 * second);
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
        neighborResponseStatisticsNext[neighborID - 1] += alpha;
        // dbg(NEIGHBOR_CHANNEL, "Current statistics on neighbor %d: %d\n", neighborID, currentStats);
    }
    command void NeighborDiscovery.printNeighbors() {
        int i;
        for (i = 0; i < NUM_NODES; i++) {
            if (_isNeighbor(i)){
                dbg(NEIGHBOR_CHANNEL, "I am neighbors with node: %d\n", i + 1);
            }
        }
    }
}




