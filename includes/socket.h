#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
    FIN_SENT
};


typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint8_t addr;
}socket_addr_t;

// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

typedef struct ack_data_t{
    uint32_t initialTime;
    socket_t sock;
    bool measureRTT;
}ack_data_t;

typedef struct incoming_connection_t{
    socket_port_t port;
    socket_t sock;
}incoming_connection_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    int lastWritten;
    int lastAck;
    int lastSent;
    uint8_t writeSegment;

    // If we resend a segment, we need to keep track of the amount of bytes that were not acked
    uint8_t lostAckBytes;

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    int lastRead;
    int lastRcvd;
    int nextExpected;
    uint8_t readSegment;

    uint16_t RTT;
    float RTTvar;

    uint8_t effectiveWindow;
    // Timestamp at which the socket went into CLOSED state
    // After one minute, the socket will be wiped from memory
    uint32_t closeTime;

    // # of packets which have not yet been acked
    uint8_t packetsInFlight;
    // Max # of packetsInFlight we are allowed to have
    float congestionWindow;
    // Whether we are currently in slow start phase
    bool slowStart;

    // Timestamp to measure timeout from
    uint32_t timeoutFrom;
    // Timestamp of last packet loss
    uint32_t lastPacketLoss;
    // Packets in flight when last packet was lost
    // This parameter will be set to 0 after all the deadPacketsInFlight have "timed out"
    uint8_t deadPacketsInFlight;
    uint8_t duplicateAcks;

}socket_store_t;

#endif
