#include "../../includes/packet.h"

interface NeighborDiscovery {
    command void start();
    command void reply(pack* neighborPacket);
    command void readReply(pack* confirmationPacket);
    command void printNeighbors();
    command float* statistics();
}