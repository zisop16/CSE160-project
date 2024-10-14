#include "../../includes/packet.h"

interface NeighborDiscovery {
    command void start();
    command void reply(pack* neighborPacket);
    command void readReply(pack* confirmationPacket);
    command void printNeighbors();
    // Statistics gives 8 bit weights for all neighbors on how neighborly they are
    // A value of 255 is == infinity
    // We want it to be the case that if A, B, C are weights
    // Then A + B == C only if probability(linkA) * probability(linkB) == probability(linkC)
    // -lg(linkA) - lg(linkB) == -lg(linkC)
    // -> A == -lg(linkA)
    // This makes it so that higher weights correspond to less neighborness
    command float* statistics();
}