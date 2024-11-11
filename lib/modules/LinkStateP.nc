module LinkStateP {
    provides interface LinkState;
    uses interface NeighborDiscovery;
    uses interface Flooding;
    uses interface Socket;
    uses interface Timer<TMilli> as sendTimer;
    uses interface SimpleSend as Sender;
}

implementation {
    uint8_t neighborData[neighborBytes * NUM_NODES];

    // routingTable[5] == K means if a packet has target 
    // note: NodeID == (5 + 1)
    // Then we send all packets with target 6 towards neighbor node K
    uint8_t routingTable[NUM_NODES];

    const uint8_t ROUTE_UNREACHABLE = 255;
    
    command void LinkState.printRouteTable() {
        uint8_t i;
        for (i = 0; i < NUM_NODES; i++) {
            dbg(ROUTING_CHANNEL, "%d -> %d\n", i + 1, routingTable[i]);
        }
    }

    uint8_t* neighborInfo(uint8_t nodeIndex) {
        uint16_t index = (nodeIndex) * neighborBytes;
        if (nodeIndex == TOS_NODE_ID - 1) {
            return call NeighborDiscovery.getNeighbors();
        }
        return neighborData + index;
    }

    uint8_t edgeExists(uint8_t from, uint8_t to) {
        uint8_t* infoFrom = neighborInfo(from);
        uint8_t byteIndex = to / 8;
        uint8_t bitIndex = to % 8;
        uint8_t exists = (infoFrom[byteIndex] >> bitIndex) & 1;
        return exists;
    }

    // Djikstra's algorithm distances for each node
    uint8_t distances[NUM_NODES];
    // "Hashset" for whether each node has been seen
    uint8_t seen[NUM_NODES];

    void calculateRoutingTable() {
        uint8_t i;
        uint8_t self = TOS_NODE_ID - 1;
        uint8_t minDist;
        uint8_t minDistNode;
        uint8_t comparisonDistance;
        uint8_t unseen = NUM_NODES - 1;
        for (i = 0; i < NUM_NODES; i++) {
            if (i == self) {
                distances[i] = 0;
                seen[self] = 1;
                // We do not advertise a route to ourself
                // I'm not sure if I will actually use this
                // This value can basically be anything
                routingTable[i] = 255;
            }
            else if (edgeExists(self, i)) {
                distances[i] = 1;
                seen[i] = 0;
                routingTable[i] = i;
            } else {
                distances[i] = 254;
                seen[i] = 0;
                routingTable[i] = ROUTE_UNREACHABLE - 1;
            }
        }
        

        while(unseen > 0) {
            minDist = 255;
            for (i = 0; i < NUM_NODES; i++) {
                if (!seen[i]) {
                    if (distances[i] < minDist) {
                        minDist = distances[i];
                        minDistNode = i;
                    }
                }
            }
            seen[minDistNode] = 1;
            for (i = 0; i < NUM_NODES; i++) {
                if (edgeExists(minDistNode, i)) {
                    comparisonDistance = 1 + distances[minDistNode];
                    if (comparisonDistance < distances[i]) {
                        distances[i] = comparisonDistance;
                        routingTable[i] = routingTable[minDistNode];
                        
                    }
                }
            }
            unseen -= 1;
        }
        // Routing tables are currently indices, but the node IDs are 1 bigger, so we make them all 1 bigger.
        for (i = 0; i < NUM_NODES; i++) {
            routingTable[i] += 1;
        }
    }

    command void LinkState.start() {
        call sendTimer.startOneShot(100 * second);
    }
    command void LinkState.receiveUpdate(floodPack* update) {
        uint8_t sourceID = update->origin;
        uint8_t* data = update->message;
        uint16_t i;
        uint16_t j;
        uint16_t offset;

        offset = neighborBytes;
        offset *= sourceID - 1;
        offset -= 0;

        memcpy(neighborData + (offset), data, neighborBytes);
        
        calculateRoutingTable();
        
    }
    pack sendPacket;
    uint16_t localSequenceNumber = 0;
    command void LinkState.sendMessage(uint8_t target, uint8_t protocol, uint8_t* message) {
        uint8_t TTL = 18;
        // Remember that NODE_ID == index + 1
        uint8_t nextHop = routingTable[target - 1];
        if (nextHop == ROUTE_UNREACHABLE) {
            dbg(ROUTING_CHANNEL, "Attempted to send a message to node: %d, but no route is currently known\n", target);
            call LinkState.printRouteTable();
            return;
        }
        // It is not clear that this will actually be useful.
        localSequenceNumber += 1;
        makePack(&sendPacket, TOS_NODE_ID, target, TTL, protocol, localSequenceNumber, message, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPacket, nextHop);
    }

    command void LinkState.handleRoutingPacket(pack* directRoutePacket) {
        uint8_t target = directRoutePacket->dest;
        uint8_t source = directRoutePacket->src;
        uint8_t nextHop;
        uint8_t* msg;
        if (target == TOS_NODE_ID) {
            msg = directRoutePacket->payload;
            switch(directRoutePacket->protocol) {
                case PROTOCOL_DIRECTROUTE: {
                    dbg(ROUTING_CHANNEL, "Node %d sent me a message: %s\n", source, msg);
                    break;
                }
                case PROTOCOL_TCP: {
                    call Socket.handleTCP(msg);
                    break;
                }
            }
            
            return;
        }
        nextHop = routingTable[target - 1];
        if (nextHop == ROUTE_UNREACHABLE) {
            dbg(ROUTING_CHANNEL, "Attempted to send a message to node: %d, but no route is currently known\n", target);
            call LinkState.printRouteTable();
            return;
        }
        call Sender.send(*directRoutePacket, nextHop);
    }

    event void sendTimer.fired() {
        int i;
        uint8_t* neighbors = call NeighborDiscovery.getNeighbors();

        call Flooding.flood(PROTOCOL_LINKSTATE, AM_BROADCAST_ADDR, neighbors, neighborBytes);
        call sendTimer.startOneShot(30 * second);
    }
}
