#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
	
int main(int argc, char *argv[])
{
	if (argc < 4) {
		printf("Usage: %s <server port> <payload size> <number of times>\n", argv[0]);
		return 1;
	}
        int server_port = atoi(argv[1]);
	int size = atoi(argv[2]);
	int n_times = atoi(argv[3]);

	int sock, connected, bytes_received, true = 1;
	char send_data[2] , recv_data[1048576];

	struct sockaddr_in server_addr,client_addr;
	int sin_size;

	if ((sock = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
		perror("Socket");
		exit(1);
	}

	if (setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &true, sizeof(int)) == -1) {
		perror("Setsockopt");
		exit(1);
	}

	server_addr.sin_family = AF_INET;	 
	server_addr.sin_port = htons(server_port);     
	server_addr.sin_addr.s_addr = INADDR_ANY; 
	bzero(&(server_addr.sin_zero), 8); 

	if (bind(sock, (struct sockaddr *)&server_addr, sizeof(struct sockaddr)) == -1) {
		perror("Unable to bind");
		exit(1);
	}

	if (listen(sock, 5) == -1) {
		perror("Listen");
		exit(1);
	}

	printf("\nTCPServer Waiting for client on port %d\n", server_port);
	send_data[0] = 'O';
	send_data[1] = 'K';

	int i, bytes_rec;
	for (i = 0; i < n_times; i++) {
		sin_size = sizeof(struct sockaddr_in);
		connected = accept(sock, (struct sockaddr *)&client_addr,&sin_size);
		bytes_rec = recv(connected, recv_data, size, 0);
		printf("Bytes received = %d\n", bytes_rec);
		send(connected, send_data, 2, 0); 
		close(connected);
	}
	sleep(1);
	close(sock);
	return 0;
}
