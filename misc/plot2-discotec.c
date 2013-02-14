#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

int main(int argc, char *argv[]) {
	
	if (argc < 2) {
		fprintf(stderr, "Usage: %s <size> <n_times>\n", argv[0]);
		exit(EXIT_FAILURE);
	}
	int size = atoi(argv[1]);
	int n_times = atoi(argv[2]);
	int i;
	int fd1 = open("/home/unine/rand_files/rand_50MB.dat", O_RDONLY);
	read(fd1, str1, 5);
	for (i=0; i < 0/*n_times*/; i++) {
		int fd1 = open("/home/unine/rand_files/rand_50MB.dat", O_RDONLY);
		int fd2 = open("/home/unine/testflexifs/out.dat", O_WRONLY | O_CREAT);
		printf("file desc1=%d\n", fd1);
		printf("file desc2=%d\n", fd2);
		char str1[20];
		str1[0] = 'a';
		str1[1] = 'a';
		str1[2] = 'a';
		str1[3] = 'a';
		str1[4] = 'a';
		str1[5] = 'a';
		sleep(1);
		sleep(1);
		lseek(fd1, atol(argv[4]), SEEK_SET);
		sleep(1);
		int res1 = write(fd2, argv[3], strlen(argv[3]));
		perror("write");
		printf("res=%d\n", res1);
		sleep(1);
		close(fd2);
		printf("%c\n",str1[0]);
		printf("%c\n",str1[1]);
		printf("%c\n",str1[2]);
		printf("%c\n",str1[3]);
		printf("%c\n",str1[4]);
		printf("%c\n",str1[5]);
	}
	close(fd1);
	return 0;



	if (strcmp(argv[1], "rmdir") == 0) {
		printf("dir to remove = \"%s\"\n", argv[1]);
		if (rmdir(argv[2]) == -1) {
			printf("error code = %d\n", errno);
			perror("rmdir");
			exit(EXIT_FAILURE);
		}
	}
	else if (strcmp(argv[1], "link") == 0) {
		if (link(argv[2], argv[3]) == -1) {
			printf("error code = %d\n", errno);
			perror("link");
			exit(EXIT_FAILURE);
		}
	}
	else if (strcmp(argv[1], "open") == 0) {
		int fd1 = open(argv[2], O_RDWR);
		if (fd1 == -1) {
			printf("error code = %d\n", errno);
			perror("open");
		}
		sleep(1);
		fd1 = open(argv[2], O_RDONLY);
		if (fd1 == -1) {
			printf("error code = %d\n", errno);
			perror("open");
		}
		sleep(1);
		fd1 = open(argv[2], O_WRONLY);
		if (fd1 == -1) {
			printf("error code = %d\n", errno);
			perror("open");
			exit(EXIT_FAILURE);
		}
		sleep(1);
		close(fd1);
	}
	else if (strcmp(argv[1], "write") == 0) {
		int fd1 = open(argv[2], O_RDWR);
		printf("file desc=%d\n", fd1);
		char str1[20];
		str1[0] = 'a';
		str1[1] = 'a';
		str1[2] = 'a';
		str1[3] = 'a';
		str1[4] = 'a';
		str1[5] = 'a';
		sleep(1);
		read(fd1, str1, 5);
		sleep(1);
		lseek(fd1, atol(argv[4]), SEEK_SET);
		sleep(1);
		int res1 = write(fd1, argv[3], strlen(argv[3]));
		perror("write");
		printf("res=%d\n", res1);
		sleep(1);
		close(fd1);
		printf("%c\n",str1[0]);
		printf("%c\n",str1[1]);
		printf("%c\n",str1[2]);
		printf("%c\n",str1[3]);
		printf("%c\n",str1[4]);
		printf("%c\n",str1[5]);
		/*char char1 = fgetc(fp1);
		printf("%c\n", char1);
		char1 = fgetc(fp1);
		printf("%c\n", char1);
		char1 = fgetc(fp1);
		printf("%c\n", char1);
		fseek(fp1, atol(argv[4]), SEEK_SET);
		printf("%s\n", argv[3]);
		write(fp1, "%s\n", argv[3]);

		if (fprintf(fp1, "%s", argv[3]) == -1) {
			perror("write");
			fclose(fp1);
			exit(EXIT_FAILURE);
		fclose(fp1);
		}*/
	}
	else if (strcmp(argv[1], "getattr") == 0) {
		struct stat sb;
		if (stat(argv[2], &sb) == -1) {
			perror("stat");
			exit(EXIT_FAILURE);
		}

		printf("File type:                ");

		switch (sb.st_mode & S_IFMT) {
		case S_IFBLK:  printf("block device\n");            break;
		case S_IFCHR:  printf("character device\n");        break;
		case S_IFDIR:  printf("directory\n");               break;
		case S_IFIFO:  printf("FIFO/pipe\n");               break;
		case S_IFLNK:  printf("symlink\n");                 break;
		case S_IFREG:  printf("regular file\n");            break;
		case S_IFSOCK: printf("socket\n");                  break;
		default:       printf("unknown?\n");                break;
		}

		printf("I-node number:            %ld\n", (long) sb.st_ino);
		printf("Mode:                     %lo (octal)\n", (unsigned long) sb.st_mode);
		printf("Link count:               %ld\n", (long) sb.st_nlink);
		printf("Ownership:                UID=%ld   GID=%ld\n", (long) sb.st_uid, (long) sb.st_gid);
		printf("Preferred I/O block size: %ld bytes\n", (long) sb.st_blksize);
		printf("File size:                %lld bytes\n", (long long) sb.st_size);
		printf("Blocks allocated:         %lld\n", (long long) sb.st_blocks);
		printf("Last status change:       %s", ctime(&sb.st_ctime));
		printf("Last file access:         %s", ctime(&sb.st_atime));
		printf("Last file modification:   %s", ctime(&sb.st_mtime));
	}
	
	exit(EXIT_SUCCESS);
}