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
/*
 * Main executable.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "splayd.h"
#include "splay.h"
#include "splay_lib.h"

int main(int argc, char *argv[])
{
	int tmp;
	lua_State *L;

	if (argc > 1) {
		if (strcmp(argv[1], "-h") == 0) {
			printf("-h: help\n-d: daemonize\n");
			return 0;
		}
		if (strcmp(argv[1], "-d") == 0) {
			/* no chdir because *.lua will no be found... */
/*            daemon(1, 0);*/
			tmp = daemon(1, 1);
		}
	}

	L = new_lua();
	run_file(L, "splayd.lua");
	printf("End of splayd (C deamon)\n");

	return 0;
}
