configuration ChatClientC {
    provides interface ChatClient;
}

implementation {
    components ChatClientP;
	components SocketC;

	components new TimerMilliC() as writeTimer;
	components new TimerMilliC() as readTimer;

    ChatClient = ChatClientP.ChatClient;
	ChatClientP.Socket -> SocketC;
	ChatClientP.writeTimer -> writeTimer;
	ChatClientP.readTimer -> readTimer;
}