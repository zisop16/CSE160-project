#include "../../includes/packet.h"
#include "../../includes/constants.h"

module FloodingP {
    provides interface Flooding;
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as acknowledgementTimer;
    uses interface NeighborDiscovery;
}

implementation {
    pack sendPacket;
    floodPack floodPacket;
    // Packet which is currently being awaited for acknowledgement
    pack awaitingPacket;
    uint16_t localSequenceNumber = 0;
    uint16_t TTL = 18;
    uint16_t highestSequenceNumbers[NUM_NODES];
    // Whether the node is currently waiting for the acknowledgement on their flood packet
    uint8_t awaitingAcknowledgement = 0;
    uint16_t acknowledgementWait = 10;

    void sendAcknowledgement(uint8_t origin, float* stats) {
        int i;
        int neighborID;
        localSequenceNumber += 1;
        for (i = 0; i < NUM_NODES; i++) {
            if (stats[i] < .5) {
                continue;
            }
            neighborID = i + 1;

            makeFloodPack(&floodPacket, TOS_NODE_ID, origin, "", 0);
            makePack(&sendPacket, TOS_NODE_ID, neighborID, TTL, PROTOCOL_FLOOD_ACKNOWLEDGE, localSequenceNumber, &floodPacket, sizeof(floodPack));
            call Sender.send(sendPacket, neighborID);
        }
    }

    command void Flooding.flood(uint8_t target, uint8_t* message, uint8_t len) {
        int i;
        uint8_t neighborID;
        uint8_t floodPackSize;
        float* stats = call NeighborDiscovery.statistics();
        if (awaitingAcknowledgement) {
            // Do not send multiple flood packets at once
            return;
        }
        localSequenceNumber += 1;
        for (i = 0; i < NUM_NODES; i++) {
            if (stats[i] < .5) {
                continue;
            }
            // node i+1 is a neighbor
            neighborID = i + 1;
            makeFloodPack(&floodPacket, TOS_NODE_ID, target, message, len);
            floodPackSize = sizeof(floodPack) + len;
            makePack(&sendPacket, TOS_NODE_ID, neighborID, TTL, PROTOCOL_FLOODING, localSequenceNumber, (uint8_t*)&floodPacket, floodPackSize);
            call Sender.send(sendPacket, neighborID);
        }
        // Cache the packet we sent out, so that we can easily re-send it if we don't get an acknowledgement
        memcpy(&awaitingPacket, &sendPacket, sizeof(pack));
        call acknowledgementTimer.startOneShot(acknowledgementWait * second);
        awaitingAcknowledgement = 1;
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
        uint16_t protocol = packet->protocol;
        int i;
        int neighborID;
        float* stats = call NeighborDiscovery.statistics();;
        

        if (dest != TOS_NODE_ID) {
            return;
        }
        if (seq <= highestSequenceNumbers[origin - 1]) {
            return;
        }
        highestSequenceNumbers[origin - 1] = seq;
        
        if (target == TOS_NODE_ID) {
            switch(protocol) {
                case PROTOCOL_FLOODING: {
                    dbg(FLOODING_CHANNEL, "Node: %i sent me a message: %s\n", origin, message);
                    sendAcknowledgement(origin, stats);
                    break;
                }
                case PROTOCOL_FLOOD_ACKNOWLEDGE: {
                    dbg(FLOODING_CHANNEL, "My message to node: %i was acknowledged\n", origin);
                    awaitingAcknowledgement = 0;
                    break;
                }
            }
            
            return;
        }
        TTL = packet->TTL - 1;
        if (TTL == 0) {
            // Drop the packet if TTL has reached 0 and we aren't the destination
            return;
        }
        packet->TTL = TTL;
        packet->src = TOS_NODE_ID;

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
    
    event void acknowledgementTimer.fired() {
        int i;
        int neighborID;
        float* stats;
        if (!awaitingAcknowledgement) {
            return;
        }
        // Didn't receive acknowledgement
        localSequenceNumber += 1;
        stats = call NeighborDiscovery.statistics();
        for (i = 0; i < NUM_NODES; i++) {
            if (stats[i] < .5) {
                continue;
            }
            neighborID = i + 1;
            awaitingPacket.seq = localSequenceNumber;
            awaitingPacket.dest = neighborID;
            call Sender.send(awaitingPacket, neighborID);
        }
        call acknowledgementTimer.startOneShot(acknowledgementWait * second);
    }
}


