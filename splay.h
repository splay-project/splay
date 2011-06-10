#ifndef SPLAY_H
#define SPLAY_H

#define SPLAY_LIBNAME "splay"

LUA_API int luaopen_splay_core(lua_State *L);
void sp_sleep(lua_State *L);
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
