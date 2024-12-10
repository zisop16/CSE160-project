module ChatClientP {
	provides interface ChatClient;
	uses interface Socket;
	uses interface Timer<TMilli> as writeTimer;
	uses interface Timer<TMilli> as readTimer;
}

implementation {
	// We will store a max of 10000 characters in the write queue
	// If you want to write more than 10000 characters, i dont care go fuck yourself
	uint8_t writeQueue[500];
	// The maximum amount of characters we can read out of a command is 1000
	// So if someone sends a message of length 1001 we are Doomed.
	uint8_t readQueue[500];
	uint16_t readIndex = 0;
	uint16_t writeIndex = 0;
	
	void write(uint8_t* letters, uint16_t length) {
		int i;
		for (i = 0; i < length; i++) {
			writeQueue[writeIndex + i] = letters[i];
		}
		writeIndex += length;
	}

	bool connected = FALSE;
	socket_t clientSocket;

	command void ChatClient.connect(socket_port_t port, uint8_t* user, uint8_t userLength) {
		clientSocket = call Socket.connect(port, serverPort, serverNode);
		dbg(APPLICATION_CHANNEL, "Connecting to the server as %s\n", user);
		write("hello ", 6);
		write(user, userLength);
		write(delimiter, 2);
		connected = TRUE;
		call writeTimer.startPeriodic(500);
		call readTimer.startPeriodic(500);
	}

	command void ChatClient.broadcast(uint8_t* message, uint16_t messageLength) {
		write("msg ", 4);
		write(message, messageLength);
		write(delimiter, 2);
	}

	command void ChatClient.whisper(uint8_t* target, uint8_t* message, uint8_t userLength, uint16_t messageLength) {
		write("whisper ", 8);
		write(target, userLength);
		write(" ", 1);
		write(message, messageLength);
		write(delimiter, 2);
	}

	command void ChatClient.listUsers() {
		write("listusr", 7);
		write(delimiter, 2);
	}

	event void writeTimer.fired() {
		uint8_t remainingSendBuffer = call Socket.getSendBufferSize(clientSocket);
		uint8_t toSend = remainingSendBuffer;
		int i;
		if (writeIndex < toSend) {
			toSend = writeIndex;
		}
		if (toSend == 0) {
			return;
		}
		// dbg(APPLICATION_CHANNEL, "Sending %d bytes\n", toSend);
		call Socket.write(clientSocket, writeQueue, toSend);
		writeIndex -= toSend;
		// Shift all characters in the write queue to the left
		for (i = 0; i < writeIndex; i++) {
			writeQueue[i] = writeQueue[i + toSend];
		}
	}

	void parseMessage(uint16_t startInd, uint16_t endInd) {
		// When a user broadcasts, the server will send back:
		// msg [username] [message]\r\n
		// When a user private messages, the server will send back:
		// whisper [username] [message]\r\n
		// When a user asks for user list, the server will send back:
		// listusr [user1] [user2] [user3] [user4]\r\n
		// Note, if a user's name contains a \0 or a space, everything could break. I am not getting paid enough money to error check this
		bool whisper = stringCompare(readQueue + startInd, "whisper", 7);
		bool msg = stringCompare(readQueue + startInd, "msg", 3);
		bool listusr = stringCompare(readQueue + startInd, "listusr", 7);
		uint16_t space;

		if (whisper) {
			
			startInd = startInd + 8;
			space = nextSpace(readQueue, startInd, endInd);
			readQueue[space] = '\0';
			readQueue[endInd + 1] = '\0';
			dbg(APPLICATION_CHANNEL, "%s (to me): %s\n", readQueue + startInd, readQueue + space + 1);

		} else if (msg) {
			startInd = startInd + 4;
			space = nextSpace(readQueue, startInd, endInd);
			readQueue[space] = '\0';
			readQueue[endInd + 1] = '\0';
			dbg(APPLICATION_CHANNEL, "%s: %s\n", readQueue + startInd, readQueue + space + 1);
		} else if (listusr) {
			startInd = startInd + 8;
			readQueue[endInd + 1] = '\0';
			dbg(APPLICATION_CHANNEL, "User List: %s\n", readQueue + startInd);
		}
		// What the fuck
	}

	void readIncomingMessages() {
		int i;
		uint8_t curr;
		uint8_t next;
		uint16_t messageStart = 0;
		for (i = 0; i < readIndex - 1; i++) {
			curr = readQueue[i];
			next = readQueue[i + 1];
			if (curr == '\r' && next == '\n') {
				parseMessage(messageStart, i - 1);
				messageStart = i + 2;
				i += 1;
			}
		}
		for (i = 0; i < readIndex - messageStart; i++) {
			readQueue[i] = readQueue[messageStart + i];
		}
		readIndex -= messageStart;
	}

	event void readTimer.fired() {
		uint8_t remainingReadBuffer = call Socket.getReceiveBufferSize(clientSocket);
		if (remainingReadBuffer == 0) {
			return;
		}
		// dbg(APPLICATION_CHANNEL, "Reading %d bytes\n", remainingReadBuffer);
		
		call Socket.read(clientSocket, readQueue + readIndex, remainingReadBuffer);
		readIndex += remainingReadBuffer;
		
		readIncomingMessages();
	}
}