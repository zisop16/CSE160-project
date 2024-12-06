module ChatClientP {
	provides interface ChatClient;
	uses interface Socket;
	uses interface Timer<TMilli> as writeTimer;
	uses interface Timer<TMilli> as readTimer;
}

implementation {
	uint8_t serverNode = 1;
	uint8_t serverPort = 41;
	// We will store a max of 10000 characters in the write queue
	// If you want to write more than 10000 characters, i dont care go fuck yourself
	uint8_t writeQueue[10000];
	// The maximum amount of characters we can read out of a command is 1000
	// So if someone sends a message of length 1001 we are Doomed.
	uint8_t readQueue[1000];
	uint16_t readIndex = 0;
	uint16_t writeIndex = 0;
	uint8_t* delimiter = "\r\n";
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
		write("hello ", 6);
		write(user, userLength);
		write(delimiter);
		connected = TRUE;
		call writeTimer.startPeriodic(500);
		call readTimer.startPeriodic(500);
	}

	command void ChatClient.broadcast(uint8_t* message, uint16_t messageLength) {
		write("msg ", 4);
		write(message, messageLength);
		write(delimiter);
	}

	command void ChatClient.whisper(uint8_t* target, uint8_t* message, uint8_t userLength, uint16_t messageLength) {
		write("whisper ", 8);
		write(target, userLength);
		write(" ", 1);
		write(message, messageLength);
		write(delimiter);
	}

	command void ChatClient.listUsers() {
		write("listusr", 7);
		write(delimiter);
	}

	event void writeTimer.fired() {
		uint8_t remainingSendBuffer = call Socket.getSendBufferSize(clientSocket);
		uint8_t toSend = remainingSendBuffer;
		int i;
		if (writeIndex < toSend) {
			toSend = writeIndex;
		}
		call Socket.write(clientSocket, writeQueue, toSend);
		writeIndex -= toSend;
		// Shift all characters in the write queue to the left
		for (i = 0; i < writeIndex; i++) {
			writeQueue[i] = writeQueue[i + toSend];
		}
	}

	bool stringCompare(uint8_t* str1, uint8_t* str2, uint16_t len) {
		int i;
		for (i = 0; i < len; i++) {
			if (str1[i] != str2[i]) {
				return FALSE;
			}
		}
		return TRUE;
	}

	int nextSpace(uint16_t from, uint16_t to) {
		int i;
		for (i = from; i <= to; i++) {
			if (readQueue[i] == ' ') {
				return i;
			}
		}
		return -1;
	}

	void parseMessage(uint16_t startInd, uint16_t endInd) {
		// When a user broadcasts, the server will send back:
		// msg [username] [message]\r\n
		// When a user private messages, the server will send back:
		// whisper [username] [message]\r\n
		// When a user asks for user list, the server will send back:
		// listusr [user1] [user2] [user3] [user4]\r\n
		// Note, if a user's name contains a \0, everything could break. I am not getting paid enough money to error check this
		bool whisper = stringCompare(readQueue + startInd, "whisper", 7);
		bool msg = stringCompare(readQueue + startInd, "msg", 3);
		bool listusr = stringCompare(readQueue + startInd, "listusr", 7);
		uint16_t space;

		if (whisper) {
			startInd = startInd + 8;
			space = nextSpace(startInd, endInd);
			readQueue[space] = '\0';
			readQueue[endInd - 1] = '\0';
			dbg(APPLICATION_CHANNEL, "%s whispered to me: %s\n", readQueue + startInd, readQueue + space + 1);

		} else if (msg) {
			startInd = startInd + 4;
			space = nextSpace(startInd, endInd);
			readQueue[space] = '\0';
			readQueue[endInd - 1] = '\0';
			dbg(APPLICATION_CHANNEL, "%s: %s\n", readQueue + startInd, readQueue + space + 1);
		} else if (listusr) {
			startInd = startInd + 8;
			readQueue[endInd - 1] = '\0';
			dbg(APPLICATION_CHANNEL, "User List: %s\n", readQueue + startInd);
		}
		// What the fuck
	}

	void readIncomingMessages() {
		int i;
		uint8_t curr;
		uint8_t next;
		uint16_t messageStart = 0;
		int lastRead = -1;
		for (i = 0; i < readIndex - 1; i++) {
			if (readIndex + i == -1) {
				continue;
			}
			curr = readQueue[readIndex + i];
			next = readQueue[readIndex + i + 1];
			if (curr == '\n' && next == '\r') {
				parseMessage(messageStart, i - 1);
				i += 1;
				messageStart = i + 1;
				lastRead = i;
			}
		}
		for (i = 0; i <= lastRead; i++) {
			readQueue[i] = readQueue[lastRead + i];
		}
		readIndex -= lastRead + 1;
	}

	event void readTimer.fired() {
		uint8_t remainingReadBuffer = call Socket.getReceiveBufferSize(clientSocket);
		call Socket.read(clientSocket, readQueue + readIndex, remainingReadBuffer);
		readIndex += remainingReadBuffer;
		readIncomingMessages();
	}
}