#include "../../includes/socket.h"

interface Socket {
	command void start();
	command socket_t connect(socket_port_t sourcePort, socket_port_t targetPort, uint8_t targetNode);
	command void listen(socket_port_t port);
	command void handleTCP(tcpPack* message, uint8_t senderNode);
}