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
#ifndef SPLAY_H
#define SPLAY_H

#define SPLAY_LIBNAME "splay"

LUA_API int luaopen_splay_core(lua_State *L);
int sp_sleep(lua_State *L);
int sp_bits_detect(lua_State *L);
int sp_endian(lua_State *L);
int sp_fork(lua_State *L);
int sp_exec(lua_State *L);
int sp_kill(lua_State *L);
int sp_alive(lua_State *L);
int sp_mkdir(lua_State *L);
/* int sp_check_ports(lua_State *L); */
/* int sp_reserve_ports(lua_State *L); */
/* int sp_free_ports(lua_State *L); */
/* int sp_next_free_ports(lua_State *L); */

#endif /* SPLAY_H */
