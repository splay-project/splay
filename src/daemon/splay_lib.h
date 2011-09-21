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
#ifndef SPLAY_LIB_H
#define SPLAY_LIB_H

int sp_set_max_mem(lua_State *L);
void *my_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
int my_panic(lua_State *L);
int my_error(lua_State *L);
void registerlib(lua_State *L, const char *name, lua_CFunction f);
lua_State *new_lua();
void run_file(lua_State *L, char *file);
void run_code(lua_State *L, const char *code);

#endif /* SPLAY_LIB_H */
