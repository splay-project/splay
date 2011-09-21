/* Splay ### v1.0.6 ###
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
/* Misc functions */

#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <limits.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "misc.h"

static const luaL_reg misc_funcs[] =
{
    {"time", misc_time},
    {NULL, NULL}
};

LUA_API int luaopen_splay_misc_core(lua_State *L)
{
    luaL_openlib(L, MISC_LIBNAME, misc_funcs, 0);
    return 0;
}

int misc_time(lua_State *L)
{
/*    struct timeval {*/
/*        time_t      tv_sec;     |+ seconds +|*/
/*        suseconds_t tv_usec;    |+ microseconds +|*/
/*    };*/
	struct timeval t;
	gettimeofday(&t, NULL);
	lua_pushnumber(L, t.tv_sec);
	lua_pushnumber(L, t.tv_usec);
	return 2;
}
