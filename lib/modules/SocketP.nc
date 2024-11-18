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

	uses interface List<incoming_connection_t> as incomingConnections;
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

	uint8_t calculateWindow(socket_store_t* data) {
		uint8_t size = data->effectiveWindow;
		return size;
	}

	socket_store_t getSocketData(socket_t sock) {
		if (call serverSockets.contains(sock)) {
			return call serverSockets.get(sock);
		} else {
			return call clientSockets.get(sock);
		}
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

	uint32_t getConnectionKey(uint8_t port, uint8_t nodeID) {
		return (((uint32_t)(port)) << 8) + (uint32_t)(nodeID);
	}

	void queueAck(socket_t sock, bool measureRTT) {
		uint32_t initialTime = call ackTimer.getNow();
		ack_data_t ackData;
		// Whether RTT and RTTvar should be measured based on this ack
		// This value is set to FALSE the first time the ack times out, making a duplicate packet
		ackData.measureRTT = measureRTT;
		ackData.initialTime = initialTime;
		ackData.sock = sock;
		call queuedAcks.pushback(ackData);
	}

	void clearAckQueue(socket_t sock) {
		uint16_t size = call queuedAcks.size();
		int i;
		ack_data_t curr;
		for (i = 0; i < size; i++) {
			curr = call queuedAcks.popback();
			if (curr.sock != sock) {
				call remainingAcks.pushback(curr);
			}
		}
		size = call remainingAcks.size();
		for (i = 0; i < size; i++) {
			curr = call remainingAcks.popback();
			call queuedAcks.pushback(curr);
		}
	}

	void dequeueAck(socket_t sock) {
		uint16_t size = call queuedAcks.size();
		int i;
		float alpha = .2;
		ack_data_t curr;
		uint32_t measuredRTT;
		uint32_t newRTT;
		float newRTTVar;
		bool client = call clientSockets.contains(sock);
		socket_store_t data;
		uint32_t oldRTT = data.RTT;
		float oldVar = data.RTTvar;
		uint32_t deviation;

		for (i = 0; i < size; i++) {
			curr = call queuedAcks.popfront();
			if (curr.sock == sock) {
				if (curr.measureRTT) {
					data = getSocketData(sock);
					measuredRTT = call ackTimer.getNow() - curr.initialTime;
					newRTT = (uint32_t)(oldRTT * (1 - alpha) + measuredRTT * alpha);
					if (measuredRTT > oldRTT) {
						deviation = measuredRTT - oldRTT;
					} else {
						deviation = oldRTT - measuredRTT;
					}
					newRTTVar = oldVar * (1 - alpha) + alpha * deviation;
					data.RTT = newRTT;
					data.RTTvar = newRTTVar;
					if (client) {
						call clientSockets.insert(sock, data);
					} else {
						call serverSockets.insert(sock, data);
					}
				}
				break;
			}
			call remainingAcks.pushback(curr);
		}
		while (!call remainingAcks.isEmpty()) {
			curr = call remainingAcks.popback();
			call queuedAcks.pushfront(curr);
		}
	}

	bool reTransmit(socket_t sock) {
		socket_store_t socketData = getSocketData(sock);
		ack_data_t ack;
		bool success;
		tcpData.srcPort = socketData.src;
		tcpData.destPort = socketData.dest.port;
		tcpData.window = calculateWindow(&socketData);
		tcpData.seq = socketData.lastAck;
		tcpData.ack = socketData.nextExpected;

		if (socketData.state != ESTABLISHED) {
			// Connection is not yet established
			switch(socketData.state) {
				case SYN_SENT: {
					tcpData.flags = SYN_FLAG;
					break;
				}
				case SYN_RCVD: {
					tcpData.flags = SYN_FLAG | ACK_FLAG;
					break;
				}
				case FIN_SENT: {
					tcpData.flags = FIN_FLAG;
				}
			}
			success = call LinkState.sendMessage(socketData.dest.addr, PROTOCOL_TCP, (uint8_t*)(&tcpData), TCP_HEADER_LENGTH);
			if (!success) {
				return FALSE;
			}
			queueAck(sock, FALSE);
		} else {

		}
		return TRUE;
	}

	command socket_t Socket.accept(socket_port_t port) {
		incoming_connection_t curr;
		uint16_t size;
		int i;
		if (!listening(port)) {
			return 0;
		}
		size = call incomingConnections.size();
		for (i = 0; i < size; i++) {
			curr = call incomingConnections.popfront();
			if (curr.port == port) {
				return curr.sock;
			}
			call incomingConnections.pushback(curr);
		}
		return 0;
	}

	command void Socket.start() {
		// Every 100ms, we poll our list of awaiting acks to see if any have timed out
		call ackTimer.startPeriodic(100);
	}

	event void ackTimer.fired() {
		uint16_t size = call queuedAcks.size();
		uint32_t time = call ackTimer.getNow();
		int i;
		uint32_t mew = 4;
		ack_data_t curr;
		bool client;
		bool success;
		socket_store_t currSocketData;
		uint32_t timeoutTime;
		for (i = 0; i < size; i++) {
			curr = call queuedAcks.popback();
			curr = call queuedAcks.get(0);
			currSocketData = getSocketData(curr.sock);
			timeoutTime = curr.initialTime + currSocketData.RTT + (uint32_t)(currSocketData.RTTvar * mew);
			if (time >= timeoutTime) {
				// Ack has timed out 

				// Send out the TCP packet again
				// This will return false if the route has been lost
				success = reTransmit(curr.sock);

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
		ack_data_t thing;
		bool success;

		uint32_t connectionKey = getConnectionKey(targetPort, targetNode);
		if (call portToClient.contains(sourcePort) || call connectionToServerSocket.contains(connectionKey) || listening(sourcePort)) {
			// If we already have a server or client socket on these ports, we should return an error.
			return 0;
		}

		socketInfo.src = sourcePort;
		target.port = targetPort;
		target.addr = targetNode;
		socketInfo.dest = target;
		socketInfo.state = SYN_SENT;
		socketInfo.effectiveWindow = SOCKET_BUFFER_SIZE;
		socketInfo.RTT = 1000;
		socketInfo.RTTvar = 0;
		
		tcpData.flags = SYN_FLAG;
		tcpData.destPort = targetPort;
		tcpData.srcPort = socketInfo.src;
		

		tcpData.seq = 0;
		tcpData.ack = 0;
		
		success = call LinkState.sendMessage(targetNode, PROTOCOL_TCP, (uint8_t*)&tcpData, TCP_HEADER_LENGTH);
		if (!success) {
			return 0;
		}
		sock = nextSocketID();
		call clientSockets.insert(sock, socketInfo);
		call portToClient.insert(sourcePort, sock);
		queueAck(sock, TRUE);
		dbg(TRANSPORT_CHANNEL, "Attempted to connect to node: %d on port: %d\n", targetNode, targetPort);
		thing = call queuedAcks.get(0);
		return sock;
	}

	command void Socket.listen(socket_port_t port) {
		call listeningPorts.pushback(port);
	}

	command void Socket.close(socket_t sock) {
		bool client = call clientSockets.contains(sock);
		bool exists = call clientSockets.contains(sock) || call serverSockets.contains(sock);
		bool success;
		socket_store_t socketInfo = getSocketData(sock);
		if (!exists) {
			return;
		}
		if (socketInfo.state != ESTABLISHED) {
			return;
		}
		socketInfo.state = FIN_SENT;
		tcpData.flags = FIN_FLAG;
		tcpData.srcPort = socketInfo.src;
		tcpData.destPort = socketInfo.dest.port;
		tcpData.seq = socketInfo.lastSent;
		tcpData.ack = socketInfo.lastAck;

		success = call LinkState.sendMessage(socketInfo.dest.addr, PROTOCOL_TCP, &tcpData, TCP_HEADER_LENGTH);

		if (client) {
			call clientSockets.insert(sock, socketInfo);
		} else {
			call serverSockets.insert(sock, socketInfo);
		}
		queueAck(sock, TRUE);
	}
	

	command void Socket.handleTCP(tcpPack* message, uint8_t senderNode) {
		socket_port_t srcPort = message->srcPort;
		socket_port_t destPort = message->destPort;
		socket_addr_t srcAddr;
		int syn = message->flags & SYN_FLAG;
		int ack = message->flags & ACK_FLAG;
		int fin = message->flags & FIN_FLAG;
		int rst = message->flags & RST_FLAG;
		bool success;
		bool sendResponse = FALSE;
		uint32_t connectionKey;

		socket_t sock;
		socket_store_t socketInfo;
		incoming_connection_t connection;

		bool listener = listening(destPort);
		bool client = call portToClient.contains(destPort);
		bool exists = listener || client;
		
		if (!exists) {
			
			// We are not listening or connected as client on this port, so we drop the packet
			return;
		}

		dbg(TRANSPORT_CHANNEL, "msg\n");
		

		srcAddr.port = srcPort;
		srcAddr.addr = senderNode;
		tcpData.destPort = srcAddr.port;
		tcpData.srcPort = destPort;

		connectionKey = getConnectionKey(srcAddr.port, srcAddr.addr);

		if (client) {
			sock = call portToClient.get(destPort);
			socketInfo = call clientSockets.get(sock);
			
		} else if (call connectionToServerSocket.contains(connectionKey)) {
			// Listening port and a server socket exists
			sock = call connectionToServerSocket.get(connectionKey);
			socketInfo = call serverSockets.get(sock);
		} else if (syn) {
			// Listening port and server socket doesnt exist AND we have been sent a SYN flag
			
			sock = nextSocketID();
			socketInfo.state = SYN_RCVD;
			socketInfo.src = destPort;
			socketInfo.dest = srcAddr;
			socketInfo.effectiveWindow = SOCKET_BUFFER_SIZE;
			socketInfo.lastWritten = 0;
			socketInfo.lastSent = 0;
			socketInfo.lastAck = 0;

			socketInfo.lastRead = 0;
			socketInfo.lastRcvd = 0;
			socketInfo.nextExpected = 0;
			call connectionToServerSocket.insert(connectionKey, sock);

		} else {
			// Drop the packet because it is fake news
			return;
		}
		// sock, socketInfo exist and are initialized
		
		// We will not use these fields for control signals, but this is what they should be
		tcpData.ack = socketInfo.nextExpected;
		tcpData.seq = socketInfo.lastSent;

		tcpData.window = socketInfo.effectiveWindow;

		if (message->flags == 0) {
			// Handle bytestream communication on an established socket
			// Must send an ack for all data packets
			sendResponse = TRUE;
			if (socketInfo.state == SYN_RCVD) {
				// Handles the edge case that we go into SYN_RCVD, then the client's ACK packet gets lost and they are established but we are not
				tcpData.flags = RST_FLAG;
			} else {

			}
		}

		if (listener && socketInfo.state == SYN_RCVD) {
			if (syn) {
				tcpData.flags = SYN_FLAG | ACK_FLAG;
				sendResponse = TRUE;
			} else if (ack) {
				socketInfo.state = ESTABLISHED;
				connection.sock = sock;
				connection.port = socketInfo.src;
				// This connection is now established on server side, so we can allow accept() to be called
				call incomingConnections.pushback(connection);
			}
			// Error
		}
		
		
		else if (client && socketInfo.state == SYN_SENT) {
			if (syn && ack) {
				tcpData.flags = ACK_FLAG;
				socketInfo.state = ESTABLISHED;
				sendResponse = TRUE;
			}
		}

		else if (fin) {
			if (socketInfo.state == FIN_SENT) {
				socketInfo.state == CLOSED;
				sendResponse = TRUE;
				tcpData.flags = ACK_FLAG;
			} else if (socketInfo.state == ESTABLISHED) {
				socketInfo.state == FIN_SENT;
				sendResponse = TRUE;
				tcpData.flags = FIN_FLAG;
			}
		} else if (ack) {
			if (socketInfo.state == FIN_SENT) {
				socketInfo.state = CLOSED;
			} else {
				// This is an ack for a data packet
			}
		} else if (client && rst) {
			// Reset the client socket to initial state
			socketInfo.state = SYN_SENT;
			socketInfo.effectiveWindow = SOCKET_BUFFER_SIZE;
			tcpData.flags = SYN_FLAG;
			tcpData.seq = 0;
			tcpData.ack = 0;
			clearAckQueue(sock);

			sendResponse = TRUE;
		} else {
			// HOW DID WE GET HERE?!?!
			return;
		}

		if (sendResponse) {
			
			success = call LinkState.sendMessage(senderNode, PROTOCOL_TCP, &tcpData, TCP_HEADER_LENGTH);
			
			if ((tcpData.flags & FIN_FLAG) || (tcpData.flags & SYN_FLAG)) {
				dbg(TRANSPORT_CHANNEL, "sent response\n");
				queueAck(sock, TRUE);
			}
			
		}
		if (client) {
			call clientSockets.insert(sock, socketInfo);
		} else {
			call serverSockets.insert(sock, socketInfo);
		}
	}
	
}