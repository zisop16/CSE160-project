#include "../../includes/socket.h"

interface Socket {
	command void start();
	command socket_t connect(socket_port_t sourcePort, socket_port_t targetPort, uint8_t targetNode);
	command socket_t accept(socket_port_t port);
	command void listen(socket_port_t port);
	command bool close(socket_t sock);
	command uint8_t getSendBufferSize(socket_t sock);
	command uint8_t getReceiveBufferSize(socket_t sock);
	command bool write(socket_t sock, uint8_t* data, uint8_t size);
	command bool read(socket_t sock, uint8_t* buff, uint8_t size);
	command void handleTCP(tcpPack* message, uint8_t senderNode);
}