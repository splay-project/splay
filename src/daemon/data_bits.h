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
#ifndef DATA_BITS_H
#define DATA_BITS_H

#define DATA_BITS_LIBNAME "splay.data_bits"

LUA_API int luaopen_splay_misc_core(lua_State *L);
int not(lua_State *L);
int or(lua_State *L);
int and(lua_State *L);
int cardinality(lua_State *L);
int pack(lua_State *L);
int unpack(lua_State *L);
int lua_set_bit(lua_State *L);
int lua_unset_bit(lua_State *L);
int lua_get_bit(lua_State *L);
int lua_from_string(lua_State *L);

void crc32gen();
u_int32_t crc32(unsigned char *block, unsigned int length);
extern u_int32_t crc_tab[256];

#endif /* DATA_BITS_H */
