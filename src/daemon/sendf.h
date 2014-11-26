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
#ifndef SENDF_H
#define SENDF_H

#define SENDF_LIBNAME "splay.sendf"
LUA_API int luaopen_splay_sendf(lua_State *L);
int sendf_copy_socket_to_socket(lua_State *L);
int sendf_copy_socket_to_file(lua_State *L);
int sendf_copy_file_to_socket(lua_State *L);	

#endif /* SENDF_H */