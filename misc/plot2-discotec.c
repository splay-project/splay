#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <math.h>

int main(int argc, char *argv[]) {
	if (argc < 3) {
		fprintf(stderr, "Usage: %s <size> <n_times>\n", argv[0]);
		exit(EXIT_FAILURE);
	}
	int size = atoi(argv[1]);
	int n_times = atoi(argv[2]);
	int fd1 = open("/home/unine/rand_files/rand_50MB.dat", O_RDONLY);
	char *str1 = malloc((size + 1) * sizeof(char));
	read(fd1, str1, size);
	int i, fd2;
	struct timeval tv0, tv1;
	double elapsed, average_sq = 0, average = 0, std_dev;
	for (i=0; i < n_times; i++) {
		gettimeofday(&tv0, NULL);
		fd2 = open("/home/unine/testflexifs/out.dat", O_WRONLY | O_CREAT);
		write(fd2, str1, size);
		close(fd2);
		gettimeofday(&tv1, NULL);
		elapsed = tv1.tv_sec - tv0.tv_sec + ((tv1.tv_usec - tv0.tv_usec)/1000000.0);
		average += elapsed;
		average_sq += elapsed * elapsed;
		if (i % (n_times / 5) == 0) {
			printf("%dth... ", i);
			fflush(stdout);
		}
	}
	average = average/n_times;
	std_dev = sqrt(fabs((average * average) - (average_sq/n_times)));
	printf("average elapsed time=%.9lf\n", average);
	printf("standard deviation=%.9lf\n", std_dev);
	close(fd1);
	free(str1);
	return 0;
}
