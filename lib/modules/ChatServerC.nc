#include "../../includes/socket.h"

configuration ChatServerC {
    provides interface ChatServer;
}

implementation {
	components ChatServerP;
	components SocketC;
	ChatServer = ChatServerP.ChatServer;

	components new TimerMilliC() as writeTimer;
	components new TimerMilliC() as readTimer;
	components new HashmapC(user_data_t, MAX_NUM_OF_SOCKETS) as users;

	ChatServerP.Socket -> SocketC;
	ChatServerP.writeTimer -> writeTimer;
	ChatServerP.readTimer -> readTimer;
	ChatServerP.users -> users;
}