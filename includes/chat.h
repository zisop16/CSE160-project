#ifndef CHAT_H
#define CHAT_H

uint8_t serverNode = 1;
uint8_t serverPort = 41;
uint8_t* delimiter = "\r\n";

typedef struct user_data_t{
    uint8_t username[40];
	uint8_t usernameLength;
    // Maximum command length 1000 :)
    uint8_t readBuffer[500];
	uint16_t readIndex;
	uint8_t writeBuffer[500];
    uint16_t writeIndex;
}user_data_t;

bool stringCompare(uint8_t* str1, uint8_t* str2, uint16_t len) {
	int i;
	for (i = 0; i < len; i++) {
		if (str1[i] != str2[i]) {
			return FALSE;
		}
	}
	return TRUE;
}

int nextSpace(uint8_t* buff, uint16_t from, uint16_t to) {
	int i;
	for (i = from; i <= to; i++) {
		if (buff[i] == ' ') {
			return i;
		}
	}
	return -1;
}

#endif