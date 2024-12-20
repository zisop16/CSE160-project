interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void flood(uint16_t destination, uint8_t len, uint8_t* payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(socket_port_t port);
   event void setTestClient(socket_port_t srcPort, uint8_t destNode, socket_port_t destPort, uint16_t maxNumber);
   event void setAppServer();
   event void setAppClient(uint8_t* username, uint8_t usernameLength);
   
}
