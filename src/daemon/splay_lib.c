/* Splay ### v1.0.1 ###
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
 * Functions used by splayd (deamon main executable).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "splay_lib.h"

int mem = 0;
int max_mem = 0;

static const luaL_reg splayd[] =
{
    {"set_max_mem", sp_set_max_mem},
    {NULL, NULL}
};

int sp_set_max_mem(lua_State *L)
{
    if (lua_isnumber(L, 1)) {
		max_mem = lua_tonumber(L, 1);
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "set_mamx_mem(max_mem) requires a number.");
		return 2;
	}
	return 0;
}

/* Custom Lua allocation function with memory limit. */
void *my_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
	(void)ud;
	(void)osize;
	
	/*if (max_mem > 0) {*/
		/*if (mem > max_mem && nsize > osize) {*/
			/*fprintf(stderr, "Too much memory used: %d (max: %d), end of process.\n", mem, max_mem);*/
			/*exit(EXIT_FAILURE);*/
		/*}*/
	/*}*/

	if (nsize > osize) {
		mem += nsize - osize;
	} else if (nsize == 0) {
		mem -= osize;
	} else {
		mem -= osize - nsize;
	}

	if (max_mem > 0 && mem > max_mem) {
		fprintf(stderr, "Too much memory used: wants %d (max: %d), end of process.\n", mem, max_mem);
		exit(EXIT_FAILURE);
	}

	if (nsize == 0) {
		free(ptr);
		return NULL;
	}
	else {
		return realloc(ptr, nsize);
	}
}

int my_panic(lua_State *L) {
	(void)L;  /* to avoid warnings */
	fprintf(stderr, "PANIC: unprotected error in call to Lua API (%s)\n",
			lua_tostring(L, -1));
	return 0;
}

int my_error(lua_State *L) {
	fprintf(stderr, "ERROR: (%s)\n",
			lua_tostring(L, -1));
	return 0;
}

/* PiL2, p. 291
 * Because these internal libs have not a separate '.so' that can be loaded
 * directly by require(), we need to provide the function to call directly in
 * the table 'package'.
 */
void registerlib(lua_State *L, const char *name, lua_CFunction f) {
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, f);
	lua_setfield(L, -2, name);
	lua_pop(L, 2);
}

/* Return a new Lua state with some libraries and common initializations. */
lua_State *new_lua()
{
	lua_State *L = lua_newstate(my_alloc, NULL);
/*    lua_atpanic(L, my_panic);*/


	/* PiL2 p. 292 */
	lua_cpcall(L, luaopen_base, NULL);
	lua_cpcall(L, luaopen_package, NULL);
	registerlib(L, "io", luaopen_io);
	registerlib(L, "os", luaopen_os);
	registerlib(L, "table", luaopen_table);
	registerlib(L, "string", luaopen_string);
	registerlib(L, "math", luaopen_math);
	registerlib(L, "debug", luaopen_debug);

	luaL_openlib(L, "splayd", splayd, 0);

	return L;
}

void run_file(lua_State *L, char *file)
{
	int error = luaL_loadfile(L, file) || lua_pcall(L, 0, 0, 0);

	if (error) {
		fprintf(stderr, "C daemon: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	if (error == LUA_ERRMEM) {
		fprintf(stderr, "C daemon: Memory error");
	}
}

void run_code(lua_State *L, const char *code)
{
	int error = luaL_loadbuffer(L, code, strlen(code), "line") || lua_pcall(L, 0, 0, 0);

	if (error) {
		fprintf(stderr, "C daemon: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	if (error == LUA_ERRMEM) {
		fprintf(stderr, "C daemon: Memory error");
	}
}
