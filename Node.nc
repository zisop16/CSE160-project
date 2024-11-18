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
}

implementation{
   pack sendPackage;

   event void Boot.booted(){
      call AMControl.start();
      call NeighborDiscovery.start();
      call LinkState.start();
      call Socket.start();

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

   event void CommandHandler.setTestServer(socket_port_t port) {
      call Socket.listen(port);
   }

   event void CommandHandler.setTestClient(socket_port_t srcPort, uint8_t target, socket_port_t destPort) {
      
      socket_t sock = call Socket.connect(srcPort, destPort, target);
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
