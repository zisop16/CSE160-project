#include "../../includes/socket.h"

configuration SocketC {
	provides interface Socket;
}

implementation {
	components SocketP;
	components LinkStateC;

	Socket = SocketP.Socket;

	components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS) as socketMap;
	components new HashmapC(socket_t, MAX_NUM_OF_SOCKETS) as portMap;

	SocketP.socketMap -> socketMap;
	SocketP.portMap -> portMap;
	SocketP.LinkState -> LinkStateC;
}