module ChatServerP {
	provides interface ChatServer;
	uses interface Socket;
	uses interface Timer<TMilli> as writeTimer;
	uses interface Timer<TMilli> as readTimer;

	uses interface Hashmap<user_data_t> as users;
}

implementation {
	
	socket_port_t serverPort = 41;
	void write(user_data_t* userData, uint8_t* letters, uint16_t length) {
		int i;
		for (i = 0; i < length; i++) {
			userData->writeBuffer[userData->writeIndex + i] = letters[i];
		}
		userData->writeIndex += length;
	}

	socket_t getSocketByName(uint8_t* name, uint8_t length) {
		uint32_t* sockets = call users.getKeys();
		int size = call users.size();
		int i;
		bool match;
		user_data_t currUser;
		for (i = 0; i < size; i++) {
			currUser = call users.get(sockets[i]);
			if (currUser.usernameLength == length) {
				match = stringCompare(currUser.username, name, length);
				if (match) {
					return sockets[i];
				}
			}
		}
		// Error if no match
		return 0;
	}

	void handleCommand(socket_t sock, uint16_t start, uint16_t end) {
		// When a user broadcasts, the server will send back:
		// msg [username] [message]\r\n
		// When a user private messages, the server will send back:
		// whisper [username] [message]\r\n
		// When a user asks for user list, the server will send back:
		// listusr [user1] [user2] [user3] [user4]\r\n
		user_data_t userData = call users.get(sock);
		uint8_t* comm = userData.readBuffer;
		bool whisper = stringCompare(comm + start, "whisper", 7);
		bool msg = stringCompare(comm + start, "msg", 3);
		bool listusr = stringCompare(comm + start, "listusr", 7);
		bool hello = stringCompare(comm + start, "hello", 5);
		socket_t target;
		uint32_t* keys;
		int numUsers;
		user_data_t targetData;
		uint16_t messageLength;
		int messageIndex;
		int usernameIndex;
		int space;
		int targetUserLength;
		int i;
		if (!hello && userData.usernameLength == 0) {
			// Users must have a username before they can use other commands
			return;
		}
		if (whisper) {
			
			// Command is of the form
			// whisper [target] [message]
			usernameIndex = start + 8;
			space = nextSpace(comm, usernameIndex, end);
			targetUserLength = space - usernameIndex;
			target = getSocketByName(comm + usernameIndex, targetUserLength);
			if (target == 0) {
				dbg(APPLICATION_CHANNEL, "Whisper command\n");
				return;
			}
			targetData = call users.get(target);
			write(&targetData, "whisper ", 8);
			write(&targetData, userData.username, userData.usernameLength);
			write(&targetData, " ", 1);
			messageLength = end - space;
			write(&targetData, comm + space + 1, messageLength);
			write(&targetData, delimiter, 2);
			call users.insert(target, targetData);
		} else if (msg) {
			// Command is of the form
			// msg [message]
			
			keys = call users.getKeys();
			numUsers = call users.size();
			for (i = 0; i < numUsers; i++) {
				target = keys[i];
				targetData = call users.get(target);
				if (targetData.usernameLength == 0) {
					continue;
				}
				write(&targetData, "msg ", 4);
				write(&targetData, userData.username, userData.usernameLength);
				write(&targetData, " ", 1);
				messageIndex = start + 4;
				messageLength = end - messageIndex + 1;
				write(&targetData, comm + messageIndex, messageLength);
				write(&targetData, delimiter, 2);
				// dbg(APPLICATION_CHANNEL, "Sending broadcast to: %s\n", targetData.username);

				call users.insert(target, targetData);
			}
			comm[end + 1] = '\0';
			// dbg(APPLICATION_CHANNEL, "Received a broadcast: %s\n", comm + messageIndex);
		} else if (listusr) {
			// Command is of the form
			// listusr
			keys = call users.getKeys();
			numUsers = call users.size();
			write(&userData, "listusr ", 8);
			for (i = 0; i < numUsers; i++) {
				target = keys[i];
				targetData = call users.get(target);
				if (targetData.usernameLength == 0) {
					continue;
				}
				write(&userData, targetData.username, targetData.usernameLength);
				write(&userData, " ", 1);
			}
			write(&userData, delimiter, 2);
			call users.insert(sock, userData);
		} else if (hello) {
			// Command is of the form
			// hello [username]
			usernameIndex = start + 6;
			targetUserLength = end - usernameIndex + 1;
			for (i = 0; i < targetUserLength; i++) {
				if (comm[usernameIndex + i] == ' ' || comm[usernameIndex + i] == '\0') {
					dbg(APPLICATION_CHANNEL, "No spaces in usernames :angery:\n");
					return;
				}
				userData.username[i] = comm[usernameIndex + i];
			}
			userData.username[i] = '\0';
			dbg(APPLICATION_CHANNEL, "Received a HELLO command from user: %s\n", userData.username);
			userData.usernameLength = targetUserLength;
			call users.insert(sock, userData);
		}
	}

	void handleReads(socket_t sock) {
		uint8_t remainingReadBuffer = call Socket.getReceiveBufferSize(sock);
		uint8_t curr;
		uint8_t next;
		uint16_t commandStart = 0;
		uint16_t remainingSize;
		user_data_t userData = call users.get(sock);
		int i;
		if (remainingReadBuffer > 0) {
			// dbg(APPLICATION_CHANNEL, "Socket %d reading %d bytes\n", sock, remainingReadBuffer);
		}
		call Socket.read(sock, userData.readBuffer + userData.readIndex, remainingReadBuffer);
		userData.readIndex += remainingReadBuffer;
		call users.insert(sock, userData);
		for (i = 0; i < userData.readIndex - 1; i++) {
			curr = userData.readBuffer[i];
			next = userData.readBuffer[i + 1];
			if (curr == '\r' && next == '\n') {
				handleCommand(sock, commandStart, i - 1);
				userData = call users.get(sock);
				commandStart = i + 2;
				i += 1;
			}
		}
		remainingSize = userData.readIndex - commandStart;
		for (i = 0; i < remainingSize; i++) {
			userData.readBuffer[i] = userData.readBuffer[i + commandStart];
		}
		userData.readIndex = remainingSize;
		call users.insert(sock, userData);
	}

	command void ChatServer.start() {
		call Socket.listen(serverPort);
		call readTimer.startPeriodic(500);
		call writeTimer.startPeriodic(500);
	}

	event void readTimer.fired() {
		socket_t newConnection;
		user_data_t currentUser;
		uint32_t* sockets;
		socket_t currSocket;
		int i;
		int size;
		currentUser.usernameLength = 0;
		currentUser.readIndex = 0;
		currentUser.writeIndex = 0;
		while (TRUE) {
			newConnection = call Socket.accept(serverPort);
			if (newConnection == 0) {
				break;
			}
			call users.insert(newConnection, currentUser);
			dbg(APPLICATION_CHANNEL, "Opened a new connection as socket %d\n", newConnection);
		}
		size = call users.size();
		sockets = call users.getKeys();
		for (i = 0; i < size; i++) {
			currSocket = sockets[i];
			handleReads(currSocket);
		}
	}

	void handleWrites(socket_t sock) {
		uint8_t remainingSize = call Socket.getSendBufferSize(sock);
		user_data_t userData = call users.get(sock);
		uint8_t toSend = remainingSize;
		int i;
		
		if (userData.writeIndex < remainingSize) {
			toSend = userData.writeIndex;
		}
		if (toSend == 0) {
			return;
		}
		// dbg(APPLICATION_CHANNEL, "Sending %d bytes\n", toSend);
		call Socket.write(sock, userData.writeBuffer, toSend);
		userData.writeIndex -= toSend;
		for (i = 0; i < userData.writeIndex; i++) {
			userData.writeBuffer[i] = userData.writeBuffer[i + toSend];
		}
		call users.insert(sock, userData);
	}

	event void writeTimer.fired() {
		uint32_t* sockets = call users.getKeys();
		uint16_t size = call users.size();
		socket_t currSocket;
		int i;
		for (i = 0; i < size; i++) {
			currSocket = sockets[i];
			handleWrites(currSocket);
		}
	}
}