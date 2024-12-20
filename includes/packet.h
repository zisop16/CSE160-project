//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


#include "protocol.h"
#include "../../includes/socket.h"
#include "channels.h"

enum{
	PACKET_HEADER_LENGTH = 6,
	TCP_HEADER_LENGTH = 7,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
	TCP_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH - TCP_HEADER_LENGTH,
	MAX_TTL = 15
};

typedef nx_struct floodPack {
	nx_uint8_t origin;
	nx_uint8_t target;
	nx_uint8_t message[0];
}floodPack;

typedef nx_struct tcpPack {
	nx_socket_port_t destPort;
	nx_socket_port_t srcPort;
	nx_int8_t seq;
	nx_int8_t ack;
	nx_uint8_t flags;
	nx_uint8_t window;
	nx_uint8_t segment;
	nx_uint8_t data[0];
}tcpPack;

uint8_t SYN_FLAG = 1 << 0;
uint8_t ACK_FLAG = 1 << 1;
uint8_t FIN_FLAG = 1 << 2;
uint8_t RST_FLAG = 1 << 3;
uint8_t UPDT_WINDOW_FLAG = 1 << 4;

typedef nx_struct pack{
	nx_uint8_t dest;
	nx_uint8_t src;
	nx_uint16_t seq;		//Sequence Number
	nx_uint8_t TTL;		//Time to Live
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input){
	dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

void logFloodPack(pack* input) {
	dbg(FLOODING_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
	Package->src = src;
	Package->dest = dest;
	Package->TTL = TTL;
	Package->seq = seq;
	Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
}

void makeFloodPack(floodPack* packet, uint8_t origin, uint8_t target, uint8_t* message, uint8_t length) {
	packet->origin = origin;
	packet->target = target;
	memcpy(packet->message, message, length);
}

enum{
	AM_PACK=6
};

#endif
