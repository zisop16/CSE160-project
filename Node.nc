/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/constants.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface Flooding;
   uses interface NeighborDiscovery;
   uses interface LinkState;
   uses interface Socket;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   uses interface Timer<TMilli> as writeTimer;
   uses interface Timer<TMilli> as readTimer;
}

implementation{
   pack sendPackage;

   event void Boot.booted(){
      call AMControl.start();
      call NeighborDiscovery.start();
      call LinkState.start();
      call Socket.start();
      if (TOS_NODE_ID == 6) {
         call writeTimer.startPeriodic(1 * second);
      } else if (TOS_NODE_ID == 3) {
         call readTimer.startPeriodic(1 * second);
      }
      

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         uint8_t protocol = (uint8_t)(myMsg-> protocol);

         switch(protocol) {
            case PROTOCOL_NEIGHBOR_DISCOVERY: {
               call NeighborDiscovery.reply(myMsg);
               break;
            }
            case PROTOCOL_NEIGHBOR_REPLY: {
               call NeighborDiscovery.readReply(myMsg);
               break;
            }
            case PROTOCOL_FLOODING:
            case PROTOCOL_LINKSTATE:
            case PROTOCOL_FLOOD_ACKNOWLEDGE: {
               call Flooding.handleFlood(myMsg);
               break;
            }
            case PROTOCOL_DIRECTROUTE:
            case PROTOCOL_TCP: {
               call LinkState.handleRoutingPacket(myMsg);
               break;
            }
         }
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      call LinkState.sendMessage(destination, PROTOCOL_DIRECTROUTE, payload, PACKET_MAX_PAYLOAD_SIZE);
   }

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.flood(uint16_t destination, uint8_t len, uint8_t *payload) {
      call Flooding.flood(PROTOCOL_FLOODING, destination, payload, len);
   }

   event void CommandHandler.printRouteTable(){
      call LinkState.printRouteTable();
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   socket_t serverSocket;
   socket_port_t serverPort = 0;

   event void CommandHandler.setTestServer(socket_port_t port) {
      call Socket.listen(port);
      serverPort = port;
   }

   socket_t clientSocket = 0;
   uint16_t written = 0;
   uint16_t maxWrite;
   bool closed = FALSE;
   uint16_t writeBuffer[SOCKET_BUFFER_SIZE / 2];

   event void CommandHandler.setTestClient(socket_port_t srcPort, uint8_t target, socket_port_t destPort, uint16_t maxNumber) {
      clientSocket = call Socket.connect(srcPort, destPort, target);
      maxWrite = maxNumber;
   }
   
   event void readTimer.fired() {
      uint8_t availableRead;
      int i;
      if (serverPort == 0) {
         return;
      }
      if (serverSocket == 0) {
         serverSocket = call Socket.accept(serverPort);
         if (serverSocket == 0) {
            return;
         }
      }
      availableRead = (call Socket.getReceiveBufferSize(serverSocket) / 2) * 2;
      if (availableRead < 2) {
         return;
      }
      
      call Socket.read(serverSocket, (uint8_t*)writeBuffer, availableRead);
      dbg(TRANSPORT_CHANNEL, "reading %d\n", writeBuffer[availableRead / 2 - 1]);
      for (i = 0; i < availableRead / 2; i++) {
         // dbg(TRANSPORT_CHANNEL, "read %d\n", writeBuffer[i]);
      }
   }

   event void writeTimer.fired() {
      uint8_t remainingWrite;
      uint8_t bytesWritten = 0;
      uint8_t* thing = (uint8_t*) writeBuffer;
      int i;
      if (clientSocket == 0) {
         return;
      }
      if (written == maxWrite) {
         if (!closed) {
            closed = call Socket.close(clientSocket);
         }
         return;
      }
      
      remainingWrite = call Socket.getSendBufferSize(clientSocket);
      // dbg(TRANSPORT_CHANNEL, "remaining %d\n", remainingWrite);
      if (remainingWrite < 2) {
         return;
      }
      
      for (i = 0; i < remainingWrite / 2; i++) {
         writeBuffer[i] = written;
         // dbg(TRANSPORT_CHANNEL, "write %d %d %d %d\n", i*2, i*2 + 1, thing[i*2], thing[i*2 + 1]);
         written += 1;
         bytesWritten += 2;
         if (written == maxWrite) {
            break;
         }
      }
      // dbg(TRANSPORT_CHANNEL, "writing %d\n", written);
      call Socket.write(clientSocket, (uint8_t*)writeBuffer, bytesWritten);
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
