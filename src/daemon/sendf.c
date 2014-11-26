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

/* gcc -Wall -shared -fPIC -o sendf.so -I/usr/include/lua5.1 -llua5.1 sendf.c */

#define _GNU_SOURCE

#include <fcntl.h>
// always include these!
#include <stdlib.h>
#include <stdio.h>
#include <sys/sendfile.h>
//#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define _POSIX_SOURCE 1
#include <errno.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h> 
#include <lualib.h>
#include "sendf.h"

int sendf_copy_socket_to_socket(lua_State *L) {
    int pipefd[2];
    if (pipe(pipefd) < 0) {
        perror("pipe");
	    exit(1);
    }
    fcntl(pipefd[1], F_SETPIPE_SZ, 1024 * 1024);

    int callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    int in_fd = lua_tointeger(L, -3);
    int out_fd = lua_tointeger(L, -2);
    size_t len = lua_tointeger(L, -1);

    //pop the first three arguments, leaving an empty stack
    lua_pop(L,3);

    //int flags = luaL_optinteger(L, 4, 0);
   // printf("copy_socket_to_socket: num1=%d num2=%d num3=%jd \n", in_fd, out_fd, len);

	/*long spliced;

	do {
		spliced = splice(in_fd, NULL, out_fd, NULL, len, flags);
	} while (spliced == -1 && errno == EINTR);

	return 1;*/



    ssize_t bytes, bytes_sent, bytes_in_pipe;
    size_t total_bytes_sent = 0;

    // Splice the data from in_fd into the pipe
    while (total_bytes_sent < len) {
        //printf("<start while>");
        if ((bytes_sent = splice(in_fd, NULL, pipefd[1], NULL,
                len - total_bytes_sent, 
                SPLICE_F_MOVE)) <= 0) {
            if (errno == EINTR || errno == EAGAIN) {
                //the yield function should be the 4th argument and should be top of the stack at this point
                //call yield with 0 arguments, 0 expected return values, no error function 
                //lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);                
                //lua_pcall(L, 0, 0, 0);
                //printf("waiting in socket to socket with %d\n",bytes_sent);
                //lua_yield(L,0);
                // Interrupted system call/try again
                // Just skip to the top of the loop and try again
                continue;
            }
            printf("Error in splice");
            perror("splice");
	    lua_pushinteger(L, -1);
           return 1;
        }

        //printf("Bytes in pipe: %d\n", bytes_sent);

        // Splice the data from the pipe into out_fd
        bytes_in_pipe = bytes_sent;
        while (bytes_in_pipe > 0) {
            if ((bytes = splice(pipefd[0], NULL, out_fd, NULL, bytes_in_pipe,
                    SPLICE_F_MOVE)) <= 0) {
                if (errno == EINTR || errno == EAGAIN) {
                    //lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);                
                    //lua_pcall(L, 0, 0, 0);
                    lua_yield(L,0);
                    // Interrupted system call/try again
                    // Just skip to the top of the loop and try again
                    continue;
                }
                printf("Error in splice");
                perror("splice");
	        lua_pushinteger(L, -1);

                return 1;
            }
            bytes_in_pipe -= bytes;
            //printf("Bytes sent: %d\n", bytes);
        }
        total_bytes_sent += bytes_sent;
        //printf("<end while>");

    }

    close(pipefd[0]);
    close(pipefd[1]);
	lua_pushnumber(L,total_bytes_sent);
    return 1;

}

int sendf_copy_socket_to_file(lua_State *L) {
    int pipefd[2];
    if (pipe(pipefd) < 0) {
        perror("pipe");
	    exit(1);
    }
    fcntl(pipefd[1], F_SETPIPE_SZ, 1024 * 1024);

    int callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    int in_fd = lua_tointeger(L, -3);
    FILE *fout = *((FILE**) lua_touserdata(L, -2));
    int out_fd = fileno(fout);
    size_t len = lua_tointeger(L, -1);

    //pop the first three arguments, leaving the reference to the yield function as top of the stack
    lua_pop(L,3);

    //int flags = luaL_optinteger(L, 4, 0);
    //printf("copy_socket_to_file: num1=%d num2=%d num3=%jd \n", in_fd, out_fd, len);

    /*long spliced;

	do {
		spliced = splice(in_fd, NULL, out_fd, NULL, len, flags);
	} while (spliced == -1 && errno == EINTR);

	return 1;*/



    ssize_t bytes, bytes_sent, bytes_in_pipe;
    size_t total_bytes_sent = 0;

    // Splice the data from in_fd into the pipe
    while (total_bytes_sent < len) {
        //printf("<start while>");
        if ((bytes_sent = splice(in_fd, NULL, pipefd[1], NULL,
                len - total_bytes_sent, 
                SPLICE_F_MOVE)) <= 0) {
            if (errno == EINTR || errno == EAGAIN) {
                //the yield function should be the 4th argument and should be top of the stack at this point
                //call yield with 0 arguments, 0 expected return values, no error function 
                //lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);                
                //lua_pcall(L, 0, 0, 0);
                //printf("waiting in socket to file with %d\n",bytes_sent);                
                lua_yield(L,0);  
                // Interrupted system call/try again
                // Just skip to the top of the loop and try again
                continue;
            }
            printf("Error in splice");
            perror("splice");
	        lua_pushinteger(L, -1);
            return 1;
        }

        //printf("Bytes in pipe: %d\n", bytes_sent);

        // Splice the data from the pipe into out_fd
        bytes_in_pipe = bytes_sent;
        while (bytes_in_pipe > 0) {
            if ((bytes = splice(pipefd[0], NULL, out_fd, NULL, bytes_in_pipe,
                    SPLICE_F_MOVE)) <= 0) {
                if (errno == EINTR || errno == EAGAIN) {
                    //lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);                
                    //lua_pcall(L, 0, 0, 0);
                    lua_yield(L,0);
                    continue;
                }
                printf("Error in splice");
                perror("splice");
	            lua_pushinteger(L, -1);

                return 1;
            }
            bytes_in_pipe -= bytes;
            //printf("Bytes sent: %d\n", bytes);
        }
        total_bytes_sent += bytes_sent;
        //printf("<end while>");

    }

    close(pipefd[0]);
    close(pipefd[1]);
	lua_pushnumber(L,total_bytes_sent);
    return 1;

}

int sendf_copy_file_to_socket(lua_State *L) {
    int pipefd[2];
    if (pipe(pipefd) < 0) {
        perror("pipe");
	    exit(1);
    }
    fcntl(pipefd[1], F_SETPIPE_SZ, 1024 * 1024);
    
    int callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    FILE *fin = *((FILE**) lua_touserdata(L, -3));
    int in_fd = fileno(fin);
    int out_fd = lua_tointeger(L, -2);
    size_t len = lua_tointeger(L, -1);
    //int flags = luaL_optinteger(L, 4, 0);
    
    //pop the first three arguments, leaving the reference to the yield function as top of the stack
    lua_pop(L,3);

    //FILE* f = fopen("/tmp/sendf.log","w");
    //printf("copy_file_to_socket: num1=%d num2=%d num3=%jd \n", in_fd, out_fd, len);
    //fclose(f);
	/*long spliced;

	do {
		spliced = splice(in_fd, NULL, out_fd, NULL, len, flags);
	} while (spliced == -1 && errno == EINTR);

	return 1;*/



    ssize_t bytes, bytes_sent, bytes_in_pipe;
    size_t total_bytes_sent = 0;
    //f = fopen("/tmp/sendf.log","a");
    //fprintf(f,"Begin loop\n");
    //fclose(f);
    // Splice the data from in_fd into the pipe
    while (total_bytes_sent < len) {
        //printf("<start while>");
        if ((bytes_sent = splice(in_fd, NULL, pipefd[1], NULL,
                len - total_bytes_sent, 
                SPLICE_F_MOVE)) <= 0) {
            if (errno == EINTR || errno == EAGAIN) {
                //lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);                
                //lua_pcall(L, 0, 0, 0);
                lua_yield(L,0);
                // Interrupted system call/try again
                // Just skip to the top of the loop and try again
                continue;
            }
            printf("Error in splice");
            perror("splice");
	    lua_pushinteger(L, -1);
           return 1;
        }

    //f = fopen("/tmp/sendf.log","a");
    //fprintf(f,"Bytes in pipe: %d\n", bytes_sent);
    //fclose(f);
        //printf("Bytes in pipe: %d\n", bytes_sent);

        // Splice the data from the pipe into out_fd
        bytes_in_pipe = bytes_sent;
        while (bytes_in_pipe > 0) {
            if ((bytes = splice(pipefd[0], NULL, out_fd, NULL, bytes_in_pipe,
                    SPLICE_F_MOVE )) <= 0) {
                if (errno == EINTR || errno == EAGAIN) {
                    //lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);                
                    //lua_pcall(L, 0, 0, 0);
                    lua_yield(L,0);                    
                    // Interrupted system call/try again
                    // Just skip to the top of the loop and try again
                    continue;
                }
                printf("Error in splice");
                perror("splice");
	        lua_pushinteger(L, -1);

                return 1;
            }
            bytes_in_pipe -= bytes;
            //printf("Bytes sent: %d\n", bytes);
        }
    //f = fopen("/tmp/sendf.log","a");
    //fprintf(f,"Bytes remaining in pipe: %d\n", bytes_in_pipe);
    //fclose(f);
        total_bytes_sent += bytes_sent;
        //printf("<end while>");

    }

    close(pipefd[0]);
    close(pipefd[1]);
	lua_pushnumber(L,total_bytes_sent);
    return 1;

}

//int luaopen_sendf(lua_State *L){
//    lua_register(L, "copy_socket_to_socket", copy_socket_to_socket);
//    lua_register(L, "copy_socket_to_file", copy_socket_to_file);
//    lua_register(L, "copy_file_to_socket", copy_file_to_socket);
//	return 0;
//}

static const luaL_Reg sendf_funcs[] =
{
    {"copy_socket_to_socket", sendf_copy_socket_to_socket},
	{"copy_socket_to_file",   sendf_copy_socket_to_file},
	{"copy_file_to_socket",   sendf_copy_file_to_socket},
    {NULL, NULL}
};
/*
* Open the sendf library
*/
LUA_API int luaopen_sendf(lua_State *L)
{
    luaL_openlib(L, SENDF_LIBNAME, sendf_funcs, 0);
    return 1;
}
