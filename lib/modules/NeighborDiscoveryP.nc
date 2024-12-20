#include "../../includes/packet.h"
#include "../../includes/constants.h"
#include "Timer.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface LinkState;
    uses interface Timer<TMilli> as discoveryTimer;
    uses interface SimpleSend as Sender;
}

implementation {
    uint16_t localSequenceNumber = 0;
    // Store 19 double for neighbor response statistics
    double neighborResponseStatistics[NUM_NODES];
    double neighborResponseStatisticsNext[NUM_NODES];
    const double NEIGHBOR_THRESHOLD = .1;

    // Neighbors is a bitmask for bools indicating whether each node is a neighbor
    // ((NUM_NODES - 1) / 8) + 1 == ceil(NUM_NODES / 8.)
    // If we have 9 nodes, we use 2 bytes
    // If we have 8 nodes, we use 1 byte
    // If we have 40 nodes, we use 5 bytes
    uint8_t neighbors[neighborBytes];
    // Alpha for exponential weighting
    const double alpha = .1;


    pack neighborDiscoveryPacket;
    pack neighborReplyPacket;

    /*
    Returns true if a difference between calculated neighbors and previously calculated neighbors was found
    */
    bool calculateNeighbors() {
        uint8_t i;
        uint8_t byteIndex = 0;
        uint8_t bitIndex;
        uint8_t currValue = 0;
        uint8_t prevValue;
        int currIsNeighbor;
        bool difference = FALSE;
        for (i = 0; i < NUM_NODES; i++) {
            if (byteIndex != i / 8) {
                prevValue = neighbors[byteIndex];
                if (prevValue != currValue) {
                    difference = TRUE;
                }
                neighbors[byteIndex] = currValue;
                currValue = 0;
            }
            byteIndex = i / 8;
            bitIndex = i % 8;
            neighborResponseStatistics[i] = neighborResponseStatisticsNext[i];
            currIsNeighbor = neighborResponseStatistics[i] > NEIGHBOR_THRESHOLD;
            currValue = currValue + (currIsNeighbor << bitIndex);
        }
        return difference;
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
        // idk???
        uint16_t TTL = 1;
        int i;
        bool diff;
        localSequenceNumber += 1;
        makePack(&neighborDiscoveryPacket, TOS_NODE_ID, AM_BROADCAST_ADDR, TTL, PROTOCOL_NEIGHBOR_DISCOVERY, localSequenceNumber, (uint8_t*)"", 0);
        call Sender.send(neighborDiscoveryPacket, AM_BROADCAST_ADDR);
        
        diff = calculateNeighbors();
        for (i = 0; i < NUM_NODES; i++) {
            neighborResponseStatisticsNext[i] = neighborResponseStatistics[i] * (1 - alpha);
        }
        if (diff) {
            call LinkState.forceRoutingUpdate();
        }
    }
    command uint8_t NeighborDiscovery.isNeighbor(uint8_t nodeID) {
        return _isNeighbor(nodeID);
    }
    
    command uint8_t* NeighborDiscovery.getNeighbors() {
        return neighbors;
    }
    
    command void NeighborDiscovery.start() {
        call discoveryTimer.startPeriodic(10 * second);
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
            if (_isNeighbor(i + 1)){
                dbg(NEIGHBOR_CHANNEL, "I am neighbors with node: %d at confidence: %f\n", i + 1, neighborResponseStatistics[i]);
            }
        }
    }
}




