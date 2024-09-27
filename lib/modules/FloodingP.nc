#include "../../includes/packet.h"
#include "../../includes/constants.h"

module FloodingP {
    provides interface Flooding;
    uses interface SimpleSend as Sender;
    uses interface NeighborDiscovery;
}

implementation {
    pack sendPacket;
    floodPack floodPacket;
    int localSequenceNumber = 0;
    uint16_t highestSequenceNumbers[NUM_NODES];

    command void Flooding.flood(uint8_t target, uint8_t* message, uint8_t len) {
        int i;
        uint8_t neighborID;
        uint8_t floodPackSize;
        float* stats = call NeighborDiscovery.statistics();
        for (i = 0; i < NUM_NODES; i++) {
            if (stats[i] < .5) {
                continue;
            }
            // node i+1 is a neighbor
            neighborID = i + 1;
            makeFloodPack(&floodPacket, TOS_NODE_ID, target, message, len);
            floodPackSize = sizeof(floodPack) + len;
            localSequenceNumber += 1;
            makePack(&sendPacket, TOS_NODE_ID, neighborID, NUM_NODES, PROTOCOL_FLOODING, localSequenceNumber, (uint8_t*)&floodPacket, floodPackSize);
            call Sender.send(sendPacket, neighborID);
        }
        // makePack(&sendPacket, TOS_NODE_ID)
    }
    command void Flooding.handleFlood(pack* packet, uint8_t len) {
        floodPack* flood = (floodPack*)packet->payload;
        uint8_t TTL;
        uint8_t origin = flood->origin;
        uint8_t target = flood->target;
        uint16_t dest = packet->dest;
        uint16_t seq = packet->seq;
        uint8_t* message = flood->message;
        uint16_t immediateSrc = packet->src;
        float* stats;
        int i;
        int neighborID;

        if (dest != TOS_NODE_ID) {
            return;
        }
        if (seq <= highestSequenceNumbers[origin - 1]) {
            return;
        }
        highestSequenceNumbers[origin - 1] = seq;
        
        if (target == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL, "Node: %i sent me a message: %s\n", origin, message);
            return;
        }
        TTL = packet->TTL - 1;
        if (TTL == 0) {
            // Drop the packet if TTL has reached 0 and we aren't the destination
            return;
        }
        packet->TTL = TTL;
        packet->src = TOS_NODE_ID;

        stats = call NeighborDiscovery.statistics();
        for (i = 0; i < NUM_NODES; i++) {
            // Don't send the flood packet to non-neighbors
            if (stats[i] < .5) {
                continue;
            }
            neighborID = i + 1;
            // Don't send the flooding packet back to the person who gave it to us
            if (neighborID == immediateSrc) {
                continue;
            }
            packet->dest = neighborID;
            // dbg(FLOODING_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
	        // packet->src, packet->dest, packet->seq, packet->TTL, packet->protocol, packet->payload);
            // Send the modified flood packet to 
            call Sender.send(*packet, neighborID);
        }
    }
}


