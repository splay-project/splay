/* Splay ### v1.1 ###
 * Copyright 2006-2011
 * http://www.splay-project.org
 */
/*
 * This file is part of Splay.
 *
 * Splay is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * Splay is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * Splay.  If not, see <http://www.gnu.org/licenses/>.
 */
/*
 * Run a new job in a sandboxed env and redirect outputs for logging.
 */
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>

#include <netinet/in.h>
#include <netdb.h> 

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "jobd.h"
#include "splay.h"
#include "splay_lib.h"


/*
 * For futur use, we could maybe control memory of loaded shared libraries
 * throught these interceptors
 *
 * The  Unix98 standard requires malloc(), calloc(), and realloc() to set errno
 * to ENOMEM upon failure.  Glibc assumes that this is done (and the glibc
 * versions of these routines do this); if you use a private malloc
 * implementation that  does  not  set  errno, then certain library routines may
 * fail without having a reason in errno.

#include <dlfcn.h>

void free(void *ptr)
{
	static void (*func)();
	if(!func) {
		func = (void (*)()) dlsym(RTLD_NEXT, "free");
	}
	fprintf(stdout, "free is called\n");     
	fflush(stdout);
	return(func(ptr));
}

void *malloc(size_t size)
{
	static void * (*func)();
	if(!func) {
		func = (void *(*)()) dlsym(RTLD_NEXT, "malloc");
	}
	fprintf(stdout, "malloc(%d) is called\n", size);     
	fflush(stdout);
	return(func(size));
}

void *realloc(void *ptr, size_t size)
{
	static void * (*func)();
	if(!func) {
		func = (void *(*)()) dlsym(RTLD_NEXT, "realloc");
	}
	fprintf(stdout, "realloc(%d) is called\n", size);     
	fflush(stdout);
	return(func(ptr, size));
}
*/

int pid = 0;

void sighandler_term(int s) {
	printf("received kill (TERM), killing child\n");
	if (pid > 0) {
		kill(pid, SIGTERM);
	}
	/* We will halt when our child is killed. */
}

int main(int argc, char *argv[]) {

	int my_pipe[2], nbytes, tmp;
	int log_fd = 0;
	char read_buffer[1024];

	int sock_fd = 0;
	int portno;
	struct sockaddr_in serv_addr;
	struct hostent *server;

	int total_sent = 0;
	int max_size = 0;
	lua_State *L;

	printf("*** Jobd C starting ***\n");

	if (argc < 2) {
		fprintf(stderr,"usage %s <job_file> [<log_file> [<hostname> <port> [<ref> <session> <max_size> [<exec> [<infos>]]]]]\n", argv[0]);
		exit(1);
	}

	/* File log (no log if file name is "-") */
	if (argc >= 3 && strcmp(argv[2], "-") != 0) {
		if ((log_fd = open(argv[2], O_WRONLY|O_CREAT, 0644)) < 0) {
			perror("open()");
			exit(1);
		}
	}

	/* Network log */
	if (argc >= 5) {

		portno = atoi(argv[4]);
		sock_fd = socket(AF_INET, SOCK_STREAM, 0);
		if (sock_fd < 0) { 
			perror("socket()");
			exit(1);
		}

		server = gethostbyname(argv[3]);

		if (server == NULL) {
			fprintf(stderr, "ERROR, no such host\n");
			exit(1);
		}

		bzero((char *) &serv_addr, sizeof(serv_addr));
		serv_addr.sin_family = AF_INET;
		bcopy((char *)server->h_addr, 
				(char *)&serv_addr.sin_addr.s_addr,
				server->h_length);
		serv_addr.sin_port = htons(portno);

		if (connect(sock_fd, (const struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
			perror("connect()");
			exit(1);
		}
			
		if (argc >= 7) {
			/* ref */
			tmp = write(sock_fd, argv[5], strlen(argv[5]));
			tmp = write(sock_fd, "\n", 1);

			/* session */
			tmp = write(sock_fd, argv[6], strlen(argv[6]));
			tmp = write(sock_fd, "\n", 1);
		}
	}

	if (argc >= 8) {
		max_size = atoi(argv[7]);
		printf("max network log: %d bytes\n", max_size);
	}

	if (pipe(my_pipe) < 0) {
		perror("pipe()");
		exit(1);
	}
	fflush(stdout);

	pid = fork();
	if (pid < 0) {

		perror("fork()");
		exit(1);

	} else if (pid == 0) { /* child */

		close(my_pipe[0]);
		close(1); /* close stdout */
		close(2); /* close stderr */
		tmp = dup(my_pipe[1]); /* new stdout */
		tmp = dup(my_pipe[1]); /* new stderr */

		if (argc >= 9 && strcmp(argv[8], "exec") == 0) {

			printf("SPLAYD SCRIPT EXEC\n");
			chmod(argv[1], S_IRUSR|S_IXUSR|S_IWUSR);
			if (argc >= 10) {
				execl(argv[1], argv[1], argv[3], argv[4], argv[9], (char *) NULL);
			} else {
				execl(argv[1], argv[1], argv[3], argv[4], (char *) NULL);
			}

		} else {
			/**** Lua application start here !!! ****/
			L = new_lua();

			lua_pushstring(L, argv[1]);
			lua_setglobal(L, "job_file");

			printf("SPLAYD LUA EXEC\n");
			run_file(L, "jobd.lua");
			printf("SPLAYD LUA END\n");
		}

		exit(0);

	} else if (pid > 0) { /* parent */

		signal(SIGTERM, sighandler_term);

		close(my_pipe[1]);
		close(0); /* close stdin */
		tmp = dup(my_pipe[0]); /* new stdin */

		while (1) {
			bzero(read_buffer, sizeof(read_buffer));
			nbytes = read(my_pipe[0], read_buffer, sizeof(read_buffer));
			if (nbytes == 0) { /* 0 only if EOF (child is dead) */
				if (argc >= 3) {
					close(log_fd);
				}
				if (argc >= 5) {
					close(sock_fd);
				}
				exit(0);
			}
			if (nbytes > 0) {
				total_sent += nbytes;

				/* NOTE: in production comment next line */
				tmp = write(1, read_buffer, nbytes);

				if (log_fd > 0) {
					nbytes = write(log_fd, read_buffer, nbytes);
					if (nbytes < 0) {
						perror("file write()");
					}
				}

				if (sock_fd > 0 && (max_size == 0 || total_sent < max_size)) {
					nbytes = write(sock_fd, read_buffer, nbytes);
					if (nbytes < 0) {
						/* TODO eventually try reconnecting... */
						perror("socket write()");
						close(sock_fd);
						sock_fd = 0;
					}
				} else {
					close(sock_fd);
					sock_fd = 0;
				}
			}
		}
	}

	return 0;
}

