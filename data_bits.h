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
