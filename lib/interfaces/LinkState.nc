interface LinkState {
    command void start();
    command void receiveUpdate(floodPack* update);
    command void sendMessage(uint8_t target, uint8_t protocol, uint8_t* message);
    command void handleRoutingPacket(pack* directRoutePacket);
    command void printRouteTable();
}