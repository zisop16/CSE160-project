#include "../../includes/socket.h"

interface Socket {
	command socket_t connect(socket_port_t sourcePort, socket_port_t targetPort, uint8_t targetNode);
	command socket_t listen(socket_port_t port);
	command void handleTCP(tcpPack* message);
}