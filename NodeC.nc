/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components FloodingC;
    components NeighborDiscoveryC;
    components LinkStateC;
    components SocketC;
    components ChatClientC;
    components ChatServerC;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new TimerMilliC() as writeTimer;
    components new TimerMilliC() as readTimer;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    Node.Flooding -> FloodingC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;
    Node.LinkState -> LinkStateC;
    Node.Socket -> SocketC;
    Node.ChatClient -> ChatClientC;
    Node.ChatServer -> ChatServerC;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    Node.writeTimer -> writeTimer;
    Node.readTimer -> readTimer;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
}
