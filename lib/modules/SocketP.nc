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
	uses interface List<socket_t> as shouldRetransmit;
}

implementation {
	socket_t nextSocketCreation = 0;
	tcpPack tcpData;

	socket_t nextSocketID() {
		nextSocketCreation += 1;
		// We want 0 to be reserved for the error code
		// We do not want multiple sockets to have the same socketID
		while (nextSocketCreation == 0 || call serverSockets.contains(nextSocketCreation) || call clientSockets.contains(nextSocketCreation)) {
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

	void updateSocket(socket_t sock, socket_store_t* data) {
		if (call serverSockets.contains(sock)) {
			call serverSockets.insert(sock, *data);
		} else {
			call clientSockets.insert(sock, *data);
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

	uint16_t clearAckQueue(socket_t sock) {
		uint16_t size = call queuedAcks.size();
		int i;
		ack_data_t curr;
		uint16_t removed = 0;
		for (i = 0; i < size; i++) {
			curr = call queuedAcks.popback();
			if (curr.sock != sock) {
				call remainingAcks.pushback(curr);
			} else {
				removed += 1;
			}
		}
		size = call remainingAcks.size();
		for (i = 0; i < size; i++) {
			curr = call remainingAcks.popback();
			call queuedAcks.pushback(curr);
		}
		return removed;
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

	socket_store_t initializeSocket() {
		socket_store_t socketInfo;
		socketInfo.RTT = 1000;
		socketInfo.RTTvar = 0;
		socketInfo.packetsInFlight = 0;
		socketInfo.congestionWindow = 1;
		socketInfo.slowStart = TRUE;
		socketInfo.deadPacketsInFlight = 0;

		socketInfo.lastWritten = -1;
		socketInfo.lastSent = -1;
		socketInfo.lastAck = -1;
		socketInfo.writeSegment = 0;

		socketInfo.lastRead = -1;
		socketInfo.lastRcvd = -1;
		socketInfo.readSegment = 0;

		socketInfo.effectiveWindow = 0;
		socketInfo.duplicateAcks = 0;

		return socketInfo;
	}

	void reTransmit(socket_t sock) {
		socket_store_t socketData = getSocketData(sock);
		ack_data_t ack;
		uint8_t writeIndex;
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
			call LinkState.sendMessage(socketData.dest.addr, PROTOCOL_TCP, (uint8_t*)(&tcpData), TCP_HEADER_LENGTH);
			queueAck(sock, FALSE);
		} else {
			socketData.deadPacketsInFlight = socketData.packetsInFlight;
			socketData.packetsInFlight = 0;
			socketData.lastPacketLoss = call ackTimer.getNow();
			socketData.lostAckBytes = socketData.lastSent - socketData.lastAck;
			socketData.lastSent = socketData.lastAck;
			socketData.congestionWindow /= 2;
			if (socketData.congestionWindow < 1) {
				socketData.congestionWindow = 1;
			}
			socketData.slowStart = FALSE;
		}
		
		updateSocket(sock, &socketData);
	}

	bool maxSockets() {
		return (call serverSockets.size() + call clientSockets.size()) == MAX_NUM_OF_SOCKETS;
	}

	uint32_t ackTimeout(socket_store_t* data) {
		float mew = 4;
		return data->RTT + (uint32_t)(data->RTTvar * mew);
	}

	uint8_t remainingReceiveBuffer(socket_store_t* socketInfo) {
		return SOCKET_BUFFER_SIZE - 1 - socketInfo->lastRcvd;
	}

	void sendData(socket_t sock) {
		socket_store_t socketInfo = getSocketData(sock);
		uint8_t sendableBytes = socketInfo.lastWritten - socketInfo.lastSent;
		uint8_t unacknowledged = socketInfo.lastSent - socketInfo.lastAck;
		uint8_t actualWindow;
		uint32_t currTime = call ackTimer.getNow();
		uint32_t timeout = ackTimeout(&socketInfo);
		int deadPackets = socketInfo.deadPacketsInFlight;
		float remainingProportion;
		uint8_t totalPacketsInFlight;
		int maximumSendablePackets;
		uint8_t packetsSent = 0;
		int payloadStart = socketInfo.lastSent + 1;
		int payloadEnd;
		int currPayloadSize;
		uint8_t currByte;
		int32_t numerator;
		int i;

		if (socketInfo.state != ESTABLISHED) {
			return;
		}

		if (socketInfo.effectiveWindow > unacknowledged) {
			actualWindow = socketInfo.effectiveWindow - unacknowledged;
		} else {
			actualWindow = 0;
		}

		// If the receiver can only receive 60 bytes, but we have 70 bytes available to send,
		// We should only send a maximum of 60 bytes.
		if (sendableBytes > actualWindow) {
			sendableBytes = actualWindow;
		}

		

		tcpData.segment = socketInfo.writeSegment;
		tcpData.srcPort = socketInfo.src;
		tcpData.destPort = socketInfo.dest.port;
		if (sendableBytes == 0) {
			
			tcpData.flags = UPDT_WINDOW_FLAG;
			tcpData.window = remainingReceiveBuffer(&socketInfo);
			call LinkState.sendMessage(socketInfo.dest.addr, PROTOCOL_TCP, (uint8_t*)&tcpData, TCP_HEADER_LENGTH);
			return;
		}

		if (deadPackets != 0) {
			// timeout + data.lastPacketLoss is the time when all deadPacketsInFlight will be "timed out"
			// If we take this (endpoint - currTime) / timeout, we get the rough proportion of dead packets which should still be in flight
			numerator = ((int32_t)timeout + (int32_t)socketInfo.lastPacketLoss - (int32_t)currTime);
			remainingProportion = numerator / (double)(timeout);
			deadPackets = (int)(remainingProportion * deadPackets);
			if (deadPackets < 0) {
				deadPackets = 0;
				socketInfo.deadPacketsInFlight = 0;
			}
		}
		tcpData.flags = 0;
		tcpData.destPort = socketInfo.dest.port;
		tcpData.srcPort = socketInfo.src;

		totalPacketsInFlight = deadPackets + socketInfo.packetsInFlight;
		maximumSendablePackets = (int)(socketInfo.congestionWindow) - totalPacketsInFlight;

		while (packetsSent < maximumSendablePackets) {
			if (sendableBytes < TCP_MAX_PAYLOAD_SIZE) {
				currPayloadSize = sendableBytes;
			} else {
				currPayloadSize = TCP_MAX_PAYLOAD_SIZE;
			}
			sendableBytes -= currPayloadSize;

			for (i = 0; i < currPayloadSize; i++) {
				currByte = payloadStart + i;
				tcpData.data[i] = socketInfo.sendBuff[currByte];
			}
			tcpData.seq = currByte;
			socketInfo.lastSent = tcpData.seq;
			dbg(TRANSPORT_CHANNEL, "Sending byte %d %d\n", tcpData.seq, (int)socketInfo.congestionWindow);
			call LinkState.sendMessage(socketInfo.dest.addr, PROTOCOL_TCP, (uint8_t*)&tcpData, currPayloadSize + TCP_HEADER_LENGTH);
			if (socketInfo.lostAckBytes == 0) {
				queueAck(sock, TRUE);
			} else {
				if (socketInfo.lostAckBytes <= currPayloadSize) {
					socketInfo.lostAckBytes = 0;
				} else {
					socketInfo.lostAckBytes -= currPayloadSize;
				}
				queueAck(sock, FALSE);
			}
			packetsSent += 1;
			if (sendableBytes == 0) {
				break;
			}
			payloadStart = payloadStart + currPayloadSize;
		}
		socketInfo.packetsInFlight += packetsSent;
		updateSocket(sock, &socketInfo);
	}
	void sweepClosedSockets() {
		uint8_t numClients = call clientSockets.size();
		uint8_t numServers = call serverSockets.size();
		int i;
		socket_t* clients = call clientSockets.getKeys();
		socket_t* servers = call serverSockets.getKeys();
		socket_store_t curr;
		uint32_t currTime = call ackTimer.getNow();
		uint32_t closeTime;
		for (i = numClients - 1; i >= 0; i--) {
			curr = call clientSockets.get(clients[i]);
			if (curr.state == CLOSED) {
				closeTime = curr.closeTime + 60 * second;
				if (currTime > closeTime) {
					dbg(TRANSPORT_CHANNEL, "Removed socket %d from memory\n", clients[i]);
					call portToClient.remove(curr.src);
					call clientSockets.remove(clients[i]);
				}
			}
		}
		for (i = numServers - 1; i>= 0; i--) {
			curr = call serverSockets.get(servers[i]);
			if (curr.state == CLOSED) {
				closeTime = curr.closeTime + 60 * second;
				if (currTime > closeTime) {
					dbg(TRANSPORT_CHANNEL, "Removed socket %d from memory\n", servers[i]);
					call connectionToServerSocket.remove(getConnectionKey(curr.dest.port, curr.dest.addr));
					call serverSockets.remove(servers[i]);
				}
			}
		}
	}

	void sendSocketData() {
		uint8_t numClients = call clientSockets.size();
		uint8_t numServers = call serverSockets.size();
		int i;
		socket_t* clients = call clientSockets.getKeys();
		socket_t* servers = call serverSockets.getKeys();
		socket_t curr;
		for (i = 0; i < numClients; i++) {
			curr = clients[i];
			sendData(curr);
		}
		for (i = 0; i < numServers; i++) {
			curr = servers[i];
			sendData(curr);
		}
	}

	

	command uint8_t Socket.getReceiveBufferSize(socket_t sock) {
		socket_store_t socketInfo = getSocketData(sock);
		uint8_t size = socketInfo.lastRcvd - socketInfo.lastRead;
		return size;
	}

	command uint8_t Socket.getSendBufferSize(socket_t sock) {
		socket_store_t socketInfo = getSocketData(sock);
		return SOCKET_BUFFER_SIZE - 1 - socketInfo.lastWritten;
	}

	command bool Socket.write(socket_t sock, uint8_t* data, uint8_t size) {
		socket_store_t socketInfo = getSocketData(sock);
		uint8_t remainingSize = call Socket.getSendBufferSize(sock);
		int writeIndex;
		int i;

		if (remainingSize < size) {
			// cannot write this much data
			return FALSE;
		}
		for (i = 0; i < size; i++) {
			writeIndex = socketInfo.lastWritten + 1 + i;
			socketInfo.sendBuff[writeIndex] = data[i];
		}
		socketInfo.lastWritten = writeIndex;

		updateSocket(sock, &socketInfo);
		return TRUE;
	}

	command bool Socket.read(socket_t sock, uint8_t* buff, uint8_t size) {
		socket_store_t socketInfo = getSocketData(sock);
		uint8_t remainingSize = call Socket.getReceiveBufferSize(sock);
		int readIndex;
		int i;
		
		if (remainingSize < size) {
			return FALSE;
		}
		for (i = 0; i < size; i++) {
			readIndex = socketInfo.lastRead + 1 + i;
			buff[i] = socketInfo.rcvdBuff[readIndex];
		}
		socketInfo.lastRead = readIndex;
		remainingSize -= size;
		if (remainingSize == 0 && socketInfo.lastRead == SOCKET_BUFFER_SIZE - 1) {
			socketInfo.lastRead = -1;
			socketInfo.lastRcvd = -1;
			socketInfo.readSegment += 1;
		}
		updateSocket(sock, &socketInfo);
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
		uint16_t pollingTime = 500;
		call ackTimer.startPeriodic(pollingTime);
		
	}

	event void ackTimer.fired() {
		uint16_t size = call queuedAcks.size();
		uint32_t time = call ackTimer.getNow();
		int i;
		ack_data_t curr;
		socket_t retransmittingSock;
		bool client;
		bool success;
		socket_store_t currSocketData;
		uint32_t timeoutTime;
		uint16_t removed;
		

		for (i = 0; i < size; i++) {
			curr = call queuedAcks.popback();
			currSocketData = getSocketData(curr.sock);
			timeoutTime = curr.initialTime + ackTimeout(&currSocketData);
			if (time >= timeoutTime) {
				// Ack has timed out 

				// Send out the TCP packet again
				removed = clearAckQueue(curr.sock);
				size -= removed;
				
				call shouldRetransmit.pushback(curr.sock);

			} else {
				call remainingAcks.pushback(curr);
			}
		}
		size = call remainingAcks.size();
		for (i = 0; i < size; i++) {
			curr = call remainingAcks.popback();
			call queuedAcks.pushback(curr);
		}
		size = call shouldRetransmit.size();
		for (i = 0; i < size; i++) {
			retransmittingSock = call shouldRetransmit.popback();
			currSocketData = getSocketData(retransmittingSock);
			reTransmit(retransmittingSock);
		}
		sweepClosedSockets();
		sendSocketData();
	}

	command socket_t Socket.connect(socket_port_t sourcePort, socket_port_t targetPort, uint8_t targetNode) {
		socket_store_t socketInfo;
		socket_addr_t target;
		socket_t sock;
		bool success;

		uint32_t connectionKey = getConnectionKey(targetPort, targetNode);
		if (call portToClient.contains(sourcePort) || call connectionToServerSocket.contains(connectionKey) || listening(sourcePort)) {
			// If we already have a server or client socket on these ports, we should return an error.
			return 0;
		}
		if (maxSockets()) {
			// Cannot connect if we have max num of sockets
			return 0;
		}
		socketInfo = initializeSocket();
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
		
		success = call LinkState.sendMessage(targetNode, PROTOCOL_TCP, (uint8_t*)&tcpData, TCP_HEADER_LENGTH);
		if (!success) {
			return 0;
		}
		sock = nextSocketID();
		call clientSockets.insert(sock, socketInfo);
		call portToClient.insert(sourcePort, sock);
		queueAck(sock, TRUE);
		dbg(TRANSPORT_CHANNEL, "Attempted to connect to node: %d on port: %d\n", targetNode, targetPort);
		return sock;
	}

	command void Socket.listen(socket_port_t port) {
		// Cannot listen and be a client on the same port
		if (call portToClient.contains(port)) {
			return;
		}
		call listeningPorts.pushback(port);
	}

	command bool Socket.close(socket_t sock) {
		bool client = call clientSockets.contains(sock);
		bool exists = call clientSockets.contains(sock) || call serverSockets.contains(sock);
		bool success;
		socket_store_t socketInfo = getSocketData(sock);
		if (!exists) {
			return FALSE;
		}
		if (socketInfo.state != ESTABLISHED) {
			return FALSE;
		}
		if (!(socketInfo.lastWritten == socketInfo.lastAck)) {
			return FALSE;
		}
		socketInfo.state = FIN_SENT;
		tcpData.flags = FIN_FLAG;
		tcpData.srcPort = socketInfo.src;
		tcpData.destPort = socketInfo.dest.port;
		tcpData.seq = socketInfo.lastSent;
		tcpData.ack = socketInfo.lastAck;

		success = call LinkState.sendMessage(socketInfo.dest.addr, PROTOCOL_TCP, (uint8_t*)&tcpData, TCP_HEADER_LENGTH);

		updateSocket(sock, &socketInfo);
		clearAckQueue(sock);
		queueAck(sock, TRUE);
		return TRUE;
	}
	

	command void Socket.handleTCP(tcpPack* message, uint8_t senderNode) {
		socket_port_t srcPort = message->srcPort;
		socket_port_t destPort = message->destPort;
		socket_addr_t srcAddr;
		int syn = message->flags & SYN_FLAG;
		int ack = message->flags & ACK_FLAG;
		int fin = message->flags & FIN_FLAG;
		int rst = message->flags & RST_FLAG;
		int updt_window = message->flags & UPDT_WINDOW_FLAG;
		bool success;
		bool sendResponse = FALSE;
		uint32_t connectionKey;
		uint8_t currByte;
		int msgLength;
		int i;
		float before;

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
			if (maxSockets()) {
				return;
			}
			sock = nextSocketID();
			socketInfo = initializeSocket();
			socketInfo.state = SYN_RCVD;
			socketInfo.src = destPort;
			socketInfo.dest = srcAddr;

			call connectionToServerSocket.insert(connectionKey, sock);
			call serverSockets.insert(sock, socketInfo);

		} else {
			// Drop the packet because it is fake news
			return;
		}
		// sock, socketInfo exist and are initialized
		
		// We will not use these fields for control signals, but this is what they should be
		tcpData.ack = socketInfo.lastRcvd;
		tcpData.seq = socketInfo.lastSent;
		
		tcpData.window = remainingReceiveBuffer(&socketInfo);
		socketInfo.effectiveWindow = message->window;

		if (message->flags == 0) {
			// Handle bytestream communication on an established socket
			// Must send an ack for all data packets
			sendResponse = TRUE;

			if (socketInfo.state == SYN_RCVD) {
				// Handles the edge case that we go into SYN_RCVD, then the client's ACK packet gets lost and they are established but we are not
				tcpData.flags = RST_FLAG;
			} else {
				tcpData.flags = ACK_FLAG;
				if (message->segment != socketInfo.readSegment) {
					if (message->segment == socketInfo.readSegment - 1) {
						tcpData.segment = message->segment;
						tcpData.ack = SOCKET_BUFFER_SIZE - 1;
					} else {
						return;
					}
				}
				else {
					msgLength = (int)message->seq - socketInfo.lastRcvd;
					// if (msgLength <= 0) {
					// 	return;
					// }
					tcpData.segment = socketInfo.readSegment;
					if ((msgLength > TCP_MAX_PAYLOAD_SIZE) || (msgLength > tcpData.window) || (msgLength <= 0)) {
						// We have received a sequence number we were not expecting, so we will drop this packet's data on the floor,
						// But we still send back an ACK duplicate so that the sender can fast resend
						tcpData.ack = socketInfo.lastRcvd;
					} else {
						for (i = 0; i < msgLength; i++) {
							currByte = socketInfo.lastRcvd + 1 + i;
							
							socketInfo.rcvdBuff[currByte] = message->data[i];
						}
						tcpData.ack = currByte;
						socketInfo.lastRcvd = currByte;
					}
					if (tcpData.window > msgLength) {
						tcpData.window -= msgLength;
					} else {
						tcpData.window = 0;
					}
				}
			}
		}
		else if (updt_window) {
			socketInfo.effectiveWindow = message->window;
		}

		else if (listener && socketInfo.state == SYN_RCVD) {
			if (syn) {
				tcpData.flags = SYN_FLAG | ACK_FLAG;
				tcpData.window = SOCKET_BUFFER_SIZE;
				tcpData.segment = 200;
				sendResponse = TRUE;
			} else if (ack) {
				socketInfo.state = ESTABLISHED;
				connection.sock = sock;
				connection.port = socketInfo.src;
				// This connection is now established on server side, so we can allow accept() to be called
				call incomingConnections.pushback(connection);
				dequeueAck(sock);
			}
			// Error
		}
		
		
		else if (client && socketInfo.state == SYN_SENT) {
			if (syn && ack) {
				tcpData.flags = ACK_FLAG;
				socketInfo.state = ESTABLISHED;
				tcpData.window = SOCKET_BUFFER_SIZE;
				tcpData.segment = 200;
				sendResponse = TRUE;
				dequeueAck(sock);
			}
		}

		else if (fin) {
			if (socketInfo.state == FIN_SENT || socketInfo.state == CLOSED) {
				socketInfo.state = CLOSED;
				socketInfo.closeTime = call ackTimer.getNow();
				sendResponse = TRUE;
				tcpData.flags = ACK_FLAG;
				tcpData.ack = socketInfo.lastRcvd + 1;
				dequeueAck(sock);
			} else if (socketInfo.state == ESTABLISHED) {
				socketInfo.state = FIN_SENT;
				sendResponse = TRUE;
				tcpData.flags = FIN_FLAG;
				clearAckQueue(sock);
			}
		} else if (ack) {
			if (socketInfo.state == FIN_SENT) {
				if (message->ack == socketInfo.lastSent + 1) {
					socketInfo.state = CLOSED;
					socketInfo.closeTime = call ackTimer.getNow();
					dequeueAck(sock);
				}
			} else {
				// This is an ack for a data packet
				if (message->segment != socketInfo.writeSegment) {
					return;
				}
				msgLength = (int)message->ack - socketInfo.lastAck;
				if (msgLength <= 0) {
					// Duplicate ack received
					socketInfo.duplicateAcks += 1;
					if (socketInfo.duplicateAcks == 3) {
						clearAckQueue(sock);
						updateSocket(sock, &socketInfo);
						reTransmit(sock);
						socketInfo = getSocketData(sock);
					}
				} else if (message->ack > socketInfo.lastSent) {
					socketInfo.lastSent = message->ack;
					socketInfo.lastAck = message->ack;
					if (socketInfo.lastAck == SOCKET_BUFFER_SIZE - 1) {
						socketInfo.lastAck = -1;
						socketInfo.lastWritten = -1;
						socketInfo.lastSent = -1;
						socketInfo.writeSegment += 1;
						socketInfo.deadPacketsInFlight = 0;
						socketInfo.packetsInFlight = 0;
						socketInfo.duplicateAcks = 0;
						
						clearAckQueue(sock);
					}
				}
				else {
					socketInfo.duplicateAcks = 0;
					// If we receive ack 13 -> 27 -> 55, we can assume ack 41 was lost in the noise
					// Therefore we don't check if the ack is too big
					socketInfo.lastAck = message->ack;
					while (msgLength > 0) {
						msgLength -= TCP_MAX_PAYLOAD_SIZE;
						dequeueAck(sock);
						if (socketInfo.slowStart) {
							socketInfo.congestionWindow += 1;
						} else {
							before = socketInfo.congestionWindow;
							socketInfo.congestionWindow += 1./socketInfo.congestionWindow;
						}
						if (socketInfo.congestionWindow > (SOCKET_BUFFER_SIZE / TCP_MAX_PAYLOAD_SIZE)) {
							socketInfo.congestionWindow = (SOCKET_BUFFER_SIZE / TCP_MAX_PAYLOAD_SIZE);
						}
						if (socketInfo.packetsInFlight > 0) {
							socketInfo.packetsInFlight -= 1;
						}
					}
					if (socketInfo.lastAck == SOCKET_BUFFER_SIZE - 1) {
						socketInfo.lastAck = -1;
						socketInfo.lastWritten = -1;
						socketInfo.lastSent = -1;
						socketInfo.writeSegment += 1;
						socketInfo.deadPacketsInFlight = 0;
						socketInfo.packetsInFlight = 0;
						socketInfo.duplicateAcks = 0;
						
						clearAckQueue(sock);
					}
				}
				
			}
		} else if (client && rst) {
			// Reset the client socket to initial state
			socketInfo = initializeSocket();
			socketInfo.state = SYN_SENT;
			tcpData.flags = SYN_FLAG;
			tcpData.seq = 0;
			tcpData.ack = 0;
			clearAckQueue(sock);
			sendResponse = TRUE;
		}

		if (sendResponse) {
			call LinkState.sendMessage(senderNode, PROTOCOL_TCP, (uint8_t*)&tcpData, TCP_HEADER_LENGTH);
			if ((tcpData.flags & FIN_FLAG) || (tcpData.flags & SYN_FLAG)) {
				queueAck(sock, TRUE);
			}
			
		}
		updateSocket(sock, &socketInfo);
	}
	
}