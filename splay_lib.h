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
