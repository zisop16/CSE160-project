#include "../../includes/packet.h"

interface NeighborDiscovery {
    command void start();
    command void reply(pack* neighborPacket);
    command void readReply(pack* confirmationPacket);
    command void printNeighbors();
    // Returns a neighbor bitmask with 1 bit for each node
    command uint8_t* getNeighbors();
    command uint8_t isNeighbor(uint8_t nodeID);

}