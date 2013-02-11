#include <fcntl.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

int main(int argc, char *argv[])
{
	if (argc < 5) {
		printf("Usage: %s <server_ip> <server_port> <size> <n_times>\n", argv[0]);
		return 1;
	}
	int server_port = atoi(argv[2]);
	int size = atoi(argv[3]);
	int n_times = atoi(argv[4]);
	int sock, bytes_received;
	char send_data[2097152], recv_data[2];
	struct hostent *host;
	struct sockaddr_in server_addr;  

	host = gethostbyname(argv[1]);

	server_addr.sin_family = AF_INET;	 
	server_addr.sin_port = htons(server_port);   
	server_addr.sin_addr = *((struct in_addr *)host->h_addr);
	bzero(&(server_addr.sin_zero),8); 

	int fp1;
	fp1 = open("../random.dat", O_RDONLY);
	read(fp1, send_data, size);
	close(fp1);

	struct timeval tv0, tv1;
	long time1 = 0;
	long time2 = 0;
	long time3 = 0;
	long time4 = 0;
	long aux_time;
	int i1, bytes_sent;
	for (i1 = 0; i1 < n_times; i1++) {
		if ((sock = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
			perror("Socket");
			exit(1);
		}
		gettimeofday(&tv0, NULL);
		printf("time0 is %lu sec %lu usec...\n", tv0.tv_sec, tv0.tv_usec);
		if (connect(sock, (struct sockaddr *)&server_addr, sizeof(struct sockaddr)) == -1) 
		{
			perror("Connect");
			exit(1);
		}
		gettimeofday(&tv1, NULL);
		aux_time = tv1.tv_usec - tv0.tv_usec;
		time1 += (aux_time >= 0 ? aux_time : 1000000 + aux_time);
		printf("time1 is %lu sec %lu usec... aux_time=%lu\n", tv1.tv_sec, tv1.tv_usec, aux_time);
		bytes_sent = send(sock, send_data, size, 0);
		printf("Bytes sent = %d\n", bytes_sent);
		gettimeofday(&tv1, NULL);
		aux_time = tv1.tv_usec - tv0.tv_usec;
		printf("time2 is %lu sec %lu usec... aux_time=%lu\n", tv1.tv_sec, tv1.tv_usec, aux_time);
		time2 += (aux_time >= 0 ? aux_time : 1000000 + aux_time);
		recv(sock, recv_data, 2, 0);
		gettimeofday(&tv1, NULL);
		aux_time = tv1.tv_usec - tv0.tv_usec;
		printf("time3 is %lu sec %lu usec... aux_time=%lu\n", tv1.tv_sec, tv1.tv_usec, aux_time);
		time3 += (aux_time >= 0 ? aux_time : 1000000 + aux_time);
		close(sock);
		gettimeofday(&tv1, NULL);
		aux_time = tv1.tv_usec - tv0.tv_usec;
		printf("time4 is %lu sec %lu usec... aux_time=%lu\n", tv1.tv_sec, tv1.tv_usec, aux_time);
		time4 += (aux_time >= 0 ? aux_time : 1000000 + aux_time);
	}
	time1 = time1/n_times;
	time2 = time2/n_times;
	time3 = time3/n_times;
	time4 = time4/n_times;
	printf("Time1=%f\n", time1/1000000.0);
	printf("Time2=%f\n", time2/1000000.0);
	printf("Time3=%f\n", time3/1000000.0);
	printf("Time4=%f\n", time4/1000000.0);
	return 0;
}
