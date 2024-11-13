module SocketP {
	provides interface Socket;
	uses interface LinkState;
	
	// ONLY for client sockets
	// Maps socket_t -> socket_store_t
	uses interface Hashmap<socket_store_t> as clientSockets;
	// Maps port -> socket_t
	uses interface Hashmap<socket_t> as portToClient;

	uses interface List<socket_port_t> as listeningPorts;
	// ONLY for server sockets
	// Maps server socket # -> socket_store_t
	uses interface Hashmap<socket_store_t> as serverSockets;
	// Maps a connection (TOS_NODE_ID, port) -> server socket #
	uses interface Hashmap<socket_t> as connectionToServerSocket;

	uses interface Timer<TMilli> as ackTimer;

	uses interface List<ack_data_t> as queuedAcks;
	uses interface List<ack_data_t> as remainingAcks;
}

implementation {
	socket_t nextSocketCreation = 0;
	tcpPack tcpData;

	socket_t nextSocketID() {
		nextSocketCreation += 1;
		// We want 0 to be reserved for the error code
		if (nextSocketCreation == 0) {
			nextSocketCreation += 1;
		}
		return nextSocketCreation;
	}

	command void Socket.start() {
		// Every millisecond, we poll our list of awaiting acks to see if any have timed out
		call ackTimer.startPeriodic(1);
	}

	event void ackTimer.fired() {
		uint16_t size = call queuedAcks.size();
		uint32_t time = call ackTimer.getNow();
		int i;
		ack_data_t curr;
		socket_store_t currSocketData;
		for (i = 0; i < size; i++) {
			curr = call queuedAcks.popback();
			if (curr.timeoutTime >= time) {
				// This ack has expired
				if (curr.lastSent == 0) {
					// Connection is not yet established
					if (call serverSockets.contains(curr.sock)) {
						currSocketData = call serverSockets.get(curr.sock);
					} else {
						currSocketData = call clientSockets.get(curr.sock);
					}
				} else {
					// Connection is established and data bytes must be re-transmitted
				}
				// Send out the TCP packet again (what if route has been lost?!!)


			} else {
				call remainingAcks.pushback(curr);
			}
		}
		size = call remainingAcks.size();
		for (i = 0; i < size; i++) {
			curr = call remainingAcks.popback();
			call queuedAcks.pushback(curr);
		}
	}

	command socket_t Socket.connect(socket_port_t sourcePort, socket_port_t targetPort, uint8_t targetNode) {
		socket_store_t socketInfo;
		socket_addr_t target;
		socket_t sock;
		bool success;
		socketInfo.src = sourcePort;
		target.port = targetPort;
		target.addr = targetNode;
		socketInfo.dest = target;
		socketInfo.state = SYN_SENT;
		socketInfo.effectiveWindow = SOCKET_BUFFER_SIZE;
		
		tcpData.flags = SYN_FLAG;
		tcpData.destPort = targetPort;
		tcpData.srcPort = socketInfo.src;

		tcpData.seq = 0;
		tcpData.ack = 0;
		
		success = call LinkState.sendMessage(targetNode, PROTOCOL_TCP, (uint8_t*)&tcpData, sizeof(tcpPack));
		if (!success) {
			return 0;
		}
		sock = nextSocketID();
		call clientSockets.insert(sock, socketInfo);
		call portToClient.insert(sourcePort, sock);
		return sock;
	}

	command void Socket.listen(socket_port_t port) {
		call listeningPorts.pushback(port);
		/*
		socket_store_t socketInfo;
		socketInfo.src = port;
		socketInfo.state = LISTEN;
		nextSocketCreation += 1;
		call clientSockets.insert(nextSocketCreation, socketInfo);
		call portToClient.insert(port, nextSocketCreation);
		return nextSocketCreation;
		*/
	}

	/*
	Whether we are currently listening on the input port
	*/
	bool listening(socket_port_t port) {
		int i;
		socket_port_t curr;
		for (i = 0; i < call listeningPorts.size(); i++) {
			curr = call listeningPorts.get(i);
			if (curr == port) {
				return TRUE;
			}
		}
		return FALSE;
	}

	command void Socket.handleTCP(tcpPack* message, uint8_t senderNode) {
		socket_port_t srcPort = message->srcPort;
		socket_port_t destPort = message->destPort;
		socket_addr_t srcAddr;
		int syn = message->flags & SYN_FLAG;
		int ack = message->flags & ACK_FLAG;
		int fin = message->flags & FIN_FLAG;
		bool success;
		uint16_t connectionKey;

		socket_t sock;
		socket_store_t socketInfo;

		bool listener = listening(destPort);
		bool client = call portToClient.contains(destPort);
		bool exists = listener || client;
		if (!exists) {
			// We are not listening or connected as client on this port, so we drop the packet
			return;
		}
		if (message->flags == 0) {
			// Handle bytestream communication on an established socket
			return;
		}
		
		if (listener) {
			if (syn) {
				socketInfo.state = SYN_RCVD;
				socketInfo.src = destPort;
				srcAddr.port = srcPort;
				srcAddr.addr = senderNode;
				socketInfo.dest = srcAddr;
				socketInfo.effectiveWindow = SOCKET_BUFFER_SIZE;

				tcpData.flags = SYN_FLAG | ACK_FLAG;
				tcpData.seq = 0;
				tcpData.ack = 0;
				tcpData.window = SOCKET_BUFFER_SIZE;
				tcpData.destPort = socketInfo.dest.port;
				tcpData.srcPort = socketInfo.src;

				success = call LinkState.sendMessage(senderNode, PROTOCOL_TCP, (uint8_t*)&tcpData, sizeof(tcpPack));
				if (!success) {
					return;
				}
				sock = nextSocketID();

				connectionKey = (((uint16_t)(srcAddr.port)) << 8) + (uint16_t)(srcAddr.addr);
				call connectionToServerSocket.insert(connectionKey, sock);
				call serverSockets.insert(sock, socketInfo);
			} else if (fin) {

			}
		}
	}
}