module SocketP {
	provides interface Socket;
	uses interface LinkState;
	// ONLY for listening sockets and client sockets
	// Maps socket_t -> socket_store_t
	uses interface Hashmap<socket_store_t> as socketMap;
	// Maps port -> socket_t
	uses interface Hashmap<socket_t> as portMap;
}

implementation {
	socket_t nextSocketCreation = 0;
	tcpPack tcpData;

	command socket_t Socket.connect(socket_port_t sourcePort, socket_port_t targetPort, uint8_t targetNode) {
		socket_store_t socketInfo;
		socket_addr_t target;
		socketInfo.src = sourcePort;
		target.port = targetPort;
		target.addr = targetNode;
		socketInfo.dest = target;
		socketInfo.state = SYN_SENT;
		
		tcpData.flags = SYN_FLAG;
		tcpData.destPort = targetPort;
		tcpData.srcPort = socketInfo.src;

		tcpData.seq = 0;
		tcpData.ack = 0;
		
		call LinkState.sendMessage(targetNode, PROTOCOL_TCP, &tcpData);
		nextSocketCreation += 1;
		call socketMap.insert(nextSocketCreation, socketInfo);
		call portMap.insert(sourcePort, nextSocketCreation);
		return nextSocketCreation;
	}

	command socket_t Socket.listen(socket_port_t port) {
		socket_store_t socketInfo;
		socketInfo.src = port;
		socketInfo.state = LISTEN;
		nextSocketCreation += 1;
		call socketMap.insert(nextSocketCreation, socketInfo);
		call portMap.insert(port, nextSocketCreation);
		return nextSocketCreation;
	}

	command void Socket.handleTCP(tcpPack* message) {
		socket_port_t srcPort = message->srcPort;
		socket_port_t destPort = message->destPort;
		int syn = message->flags & SYN_FLAG;
		int ack = message->flags & ACK_FLAG;
		int fin = message->flags & FIN_FLAG;


	}
}