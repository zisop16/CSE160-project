#include "../../includes/chat.h"

interface ChatClient {
	command void connect(socket_port_t port, uint8_t* user, uint8_t userLength);
	command void broadcast(uint8_t* message, uint16_t messageLength);
	command void whisper(uint8_t* target, uint8_t* message, uint8_t userLength, uint16_t messageLength);
	command void listUsers();
}