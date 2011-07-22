/* Splay ### v1.0.5 ###
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
/* An Lua loadable module providing low level splay C functions. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/wait.h>

#include <netinet/in.h>
#include <netinet/ip.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "splay.h"

static const luaL_reg sp_funcs[] =
{
	{"sleep", sp_sleep},
	{"bits_detect", sp_bits_detect},
	{"endian", sp_endian},
	{"fork", sp_fork},
	{"exec", sp_exec},
	{"kill", sp_kill},
	{"alive", sp_alive},
	{"mkdir", sp_mkdir},
	{NULL, NULL}
};

LUA_API int luaopen_splay_core(lua_State *L)
{
	luaL_openlib(L, SPLAY_LIBNAME, sp_funcs, 0);

	return 0;
}

/* already in LuaSocket */
int sp_sleep(lua_State *L)
{
	if (lua_isnumber(L, 1)) {
		sleep(lua_tonumber(L, 1));
	}
	return 1;
}

/* Not accurate on all systems, but anyway... better than nothing */
int sp_bits_detect(lua_State *L)
{
	lua_pushnumber(L, sizeof(int) * 8);
	return 1;
}

int sp_endian(lua_State *L)
{
	long int i = 1;
	const char *p = (const char *) &i;
	if (p[0] == 1) {
		lua_pushnumber(L, 0); /* little */
	} else {
		lua_pushnumber(L, 1); /* big */
	}
	return 1;
}

int sp_fork(lua_State *L)
{
	int pid = fork();
	if (pid == -1) {
		lua_pushnil(L);
		lua_pushfstring(L, "Fork problem: %s", strerror(errno));
		lua_pushnumber(L, errno);
		return 3;
	}
	lua_pushnumber(L, pid);
	return 1;
}

int sp_exec(lua_State *L)
{
	int i = 0;
	int num_args = lua_gettop(L);
	char **a = malloc((num_args + 1) * sizeof(int));

	/* a[0] == command */
	for (i = 1; i <= num_args; i++) {
		a[i - 1] =(char *)lua_tostring(L, i);
	}
	a[num_args] = NULL;
	if (execv(a[0], a) < 0) {
		lua_pushnil(L);
		lua_pushfstring(L, "Exec problem: %s", strerror(errno));
		lua_pushnumber(L, errno);
		return 3;
	}

	/* If no errors, exec never return... */
	return 0;
}

/*int sp_fork_pipe(lua_State *L)*/
/*{*/
/*    int pfd[2], pid;*/

/*     if (pipe(pfd) == -1) {*/
/*        lua_pushnil(L);*/
/*        lua_pushfstring(L, "Pipe problem: %s", strerror(errno));*/
/*        lua_pushnumber(L, errno);*/
/*        return 3;*/
/*    }*/

/*   pid = fork();*/

/*   if (pid == -1) { */
/*        lua_pushnil(L);*/
/*        lua_pushfstring(L, "Fork problem: %s", strerror(errno));*/
/*        lua_pushnumber(L, errno);*/
/*        return 3;*/
/*    }*/

/*   if (pid == 0) {				|+ Child reads from pipe +|*/
/*        close(pfd[1]);			|+ Close unused write end +|*/
/*        lua_pushnumber(L, pid);*/
/*        lua_pushnumber(L, pfd[0]);*/
/*        return 2;*/
/*   } else {            |+ Parent writes to pipe +|*/
/*        close(pfd[0]);          |+ Close unused read end +|*/
/*        lua_pushnumber(L, pid);*/
/*        lua_pushnumber(L, pfd[1]);*/
/*        return 2;*/
/*   }*/
/*}*/

/*int sp_write_pipe(lua_State *L)*/
/*{*/
/*    int pfd;*/
/*    char* data;*/

/*    if (lua_isnumber(L, 1) && lua_isstring(L, 2)) {*/
/*        pfd = lua_tonumber(L, 1);*/
/*        data = lua_tostring(L, 2);*/

/*    } else {*/
/*        lua_pushnil(L);*/
/*        lua_pushstring(L, "write_pipe(pfd, data) requires an int and a string.");*/
/*        return 2;*/
/*    }*/

/*    write(pdf, data);*/
/*    lua_pushboolean(L, 1);*/
/*    return 1;*/
/*}*/

/*int sp_read_pipe(lua_State *L)*/
/*{*/
/*    int pfd;*/
/*    char* data;*/

/*    if (lua_isnumber(L, 1)) {*/
/*        pfd = lua_tonumber(L, 1);*/
/*    } else {*/
/*        lua_pushnil(L);*/
/*        lua_pushstring(L, "read_pipe(pfd, data) requires an int.");*/
/*        return 2;*/
/*    }*/

/*    data = read(pdf);*/
/*    lua_pushstring(L, data);*/
/*    return 1;*/
/*}*/

int sp_kill(lua_State *L)
{
	pid_t pid, pid2;
	int r;
	int type = SIGTERM;

	if (lua_isnumber(L, 1)) {
		pid = lua_tonumber(L, 1);
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "kill(pid) requires an int.");
		return 2;
	}

	if (lua_isnumber(L, 2)) {
		type = lua_tonumber(L, 2);
	}

	r = kill(pid, type);
	if (r == 0) {
		pid2 = waitpid(pid, NULL, 0);
		if (pid == pid2) {
			lua_pushboolean(L, 1);
			return 1;
		}
	}
	lua_pushnil(L);
	lua_pushfstring(L, "Process not killed: %d - %s", pid, strerror(errno));
	lua_pushnumber(L, errno);
	return 3;
}

/* To check if a process is still running. */
int sp_alive(lua_State *L)
{
	pid_t pid;

	if (lua_isnumber(L, 1)) {
		pid = lua_tonumber(L, 1);
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "alive(pid) requires an int.");
		return 2;
	}

	if (!waitpid(pid, NULL, WNOHANG)) {
		lua_pushboolean(L, 1);
	} else {
		lua_pushboolean(L, 0);
	}
	return 1;
}

int sp_mkdir(lua_State *L)
{
	const char* dir;

	if (lua_isstring(L, 1)) {

		dir = lua_tostring(L, 1);
		if (mkdir(dir, 0755) == 0) {
			lua_pushboolean(L, 1);
			return 1;
		} else {
			lua_pushnil(L);
			lua_pushfstring(L, "Cannot create directory %s: %s", dir, strerror(errno));
			lua_pushnumber(L, errno);
			return 3;
		}
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "mkdir(dir) requires a string.");
		return 2;
	}
}
