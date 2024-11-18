interface LinkState {
    command void start();
    command void receiveUpdate(floodPack* update);
    command bool sendMessage(uint8_t target, uint8_t protocol, uint8_t* message, uint8_t length);
    command void handleRoutingPacket(pack* directRoutePacket);
    command void printRouteTable();
    command void forceRoutingUpdate();
}