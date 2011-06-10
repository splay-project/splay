#ifndef MISC_H
#define MISC_H

#define MISC_LIBNAME "splay.misc"

LUA_API int luaopen_splay_misc_core(lua_State *L);
int misc_time(lua_State *L);
#endif /* MISC_H */
