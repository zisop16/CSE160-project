#include "../../includes/socket.h"

configuration SocketC {
	provides interface Socket;
}

implementation {
	components SocketP;
	components LinkStateC;

	Socket = SocketP.Socket;

	components new ListC(incoming_connection_t, MAX_NUM_OF_SOCKETS) as incomingConnections;
	components new ListC(socket_port_t, MAX_NUM_OF_SOCKETS) as listeningPorts;
	components new ListC(ack_data_t, MAX_NUM_OF_SOCKETS * SOCKET_BUFFER_SIZE) as queuedAcks;
	components new ListC(ack_data_t, MAX_NUM_OF_SOCKETS * SOCKET_BUFFER_SIZE) as remainingAcks;
	components new ListC(socket_t, MAX_NUM_OF_SOCKETS) as shouldRetransmit;

	components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS) as clientSockets;
	components new HashmapC(socket_t, MAX_NUM_OF_SOCKETS) as portToClient;
	components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS) as serverSockets;
	components new HashmapC(socket_t, MAX_NUM_OF_SOCKETS) as connectionToServerSocket;

	components new TimerMilliC() as ackTimer;

	SocketP.clientSockets -> clientSockets;
	SocketP.portToClient -> portToClient;
	SocketP.serverSockets -> serverSockets;
	SocketP.connectionToServerSocket -> connectionToServerSocket;

	SocketP.listeningPorts -> listeningPorts;
	SocketP.queuedAcks -> queuedAcks;
	SocketP.remainingAcks -> remainingAcks;
	SocketP.incomingConnections -> incomingConnections;
	SocketP.shouldRetransmit -> shouldRetransmit;

	SocketP.LinkState -> LinkStateC;
	SocketP.ackTimer -> ackTimer;
}