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
/* Bits operation over data. Useful to implement bloom filters, crypto, ...
 * For operations on integers, luabits is better.
 */

#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <limits.h>
#include <ctype.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "data_bits.h"

#define set_bit(o, v) ((o)[(v) / 8] |= (1 << ((v) % 8)))
#define unset_bit(o, v) ((o)[(v) / 8] &= (255 ^ (1 << ((v) % 8))))
#define get_bit(o, v) (((o)[(v) / 8] & (1 << ((v) % 8))) ? 1 : 0)

static const luaL_reg misc_funcs[] =
{
	{"dnot", not},
	{"dor", or},
	{"dand", and},
	{"cardinality", cardinality},
	{"pack", pack},
	{"unpack", unpack},
	{"set_bit", lua_set_bit},
	{"unset_bit", lua_unset_bit},
	{"get_bit", lua_get_bit},
	{"from_string", lua_from_string},
	{NULL, NULL}
};

LUA_API int luaopen_splay_data_bits_core(lua_State *L)
{
	luaL_openlib(L, DATA_BITS_LIBNAME, misc_funcs, 0);
	return 0;
}

int not(lua_State *L)
{
	const char* str;
	char* nstr;
	size_t len;
	int i;

	if (lua_isstring(L, 1)) {
		str = lua_tolstring(L, 1, &len);
		nstr = malloc(len);
		for (i = 0; i < len; i++) {
			nstr[i] = ~str[i];
		}
		lua_pushlstring(L, nstr, len);
		free(nstr);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "dnot(string) requires a string.");
		return 2;
	}
}

int or(lua_State *L)
{
	const char* str;
	const char* str2;
	char* nstr;
	size_t len, len2;
	int i;

	if (lua_isstring(L, 1) && lua_isstring(L, 2)) {
		str = lua_tolstring(L, 1, &len);
		str2 = lua_tolstring(L, 2, &len2);
		if (len != len2) {
			lua_pushnil(L);
			lua_pushstring(L, "length of strings is not equal");
			return 2;
		}
		nstr = malloc(len);
		/*while (len--)*/
		/**nstr++ = *str++ | *str2++;*/
		for (i = 0; i < len; i++) {
			nstr[i] = str[i] | str2[i];
		}
		lua_pushlstring(L, nstr, len);
		free(nstr);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "dor(string, string) requires 2 strings of the same length.");
		return 2;
	}
}

int and(lua_State *L)
{
	const char* str;
	const char* str2;
	char* nstr;
	size_t len, len2;
	int i;

	if (lua_isstring(L, 1) && lua_isstring(L, 2)) {
		str = lua_tolstring(L, 1, &len);
		str2 = lua_tolstring(L, 2, &len2);
		if (len != len2) {
			lua_pushnil(L);
			lua_pushstring(L, "length of strings is not equal");
			return 2;
		}
		nstr = malloc(len);
		for (i = 0; i < len; i++) {
			nstr[i] = str[i] & str2[i];
		}
		lua_pushlstring(L, nstr, len);
		free(nstr);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "dand(string, string) requires 2 strings of the same length.");
		return 2;
	}
}

int cardinality(lua_State *L)
{
	const char* str;
	unsigned char mask;
	size_t len;
	int total = 0;
	int i;

	if (lua_isstring(L, 1)) {
		str = lua_tolstring(L, 1, &len);
		for (i = 0; i < len; i++) {
			mask = UCHAR_MAX - (UCHAR_MAX >> 1);
			while (mask) {
				total += ((str[i] & mask) ? 1 : 0);
				mask >>= 1;
			}
		}
		lua_pushnumber(L, total);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "cardinality(string) requires a string.");
		return 2;
	}
}

/* Return a string describing the position of the 1s in the bloom filter. The
 * size for these 1's position depends of the size of the bloom filter (if bf
 * size is <= 256, 1 byte is used, if > 256 and <= 65536, 2 bytes are used,
 * ...).
 */
int pack(lua_State *L)
{
	const char* str;
	unsigned char mask;
	size_t len;
	double tmp;
	int i, j, k, val;
	int count = 0; /* compute size of the result (in chars) */
	int size_pos = 1;
	char* out;
	unsigned char* pos;

	if (lua_isstring(L, 1)) {
		str = lua_tolstring(L, 1, &len);
		tmp = len * 8;
		while ((tmp /= 256) > 1) {
			size_pos++;
		}
		/* Safe choice, but a true bloomfilter is mostly empty... */
		out = malloc(len * 8 * size_pos);
		pos = (unsigned char*) out;
		for (i = 0; i < len; i++) {
			j = 0;
			mask = 1;
			while (mask) {
				if (str[i] & mask) {
					val = i * 8 + j;
					for (k = size_pos - 1; k >= 0; k--) {
						*pos = val / (pow(256, k));
						val -= *pos++ * pow(256, k);
						count++;
					}
				}
				j++;
				mask <<= 1;
			}
		}
		lua_pushlstring(L, out, count);
		free(out);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "pack(bf) requires a string.");
		return 2;
	}
}

int unpack(lua_State *L)
{
	const char* str;
	size_t len, bf_len;
	double tmp;
	int i, k, val;
	int size_pos = 1;
	char* out;

	if (lua_isstring(L, 1) && lua_isnumber(L, 2)) {
		str = lua_tolstring(L, 1, &len);

		/* length of bloom filter IN CHARS */
		bf_len = lua_tonumber(L, 2);

		tmp = bf_len * 8;
		while ((tmp /= 256) > 1) {
			size_pos++;
		}

		out = malloc(bf_len);
		bzero(out, bf_len); /* security */

		for (i = 0; i < len; i += size_pos) {
			val = 0;
			for (k = size_pos - 1; k >= 0; k--) {
				val += ((*str < 0) ? *str++ + 256 : *str++) * pow(256, k);
			}
			set_bit(out, val);
		}

		lua_pushlstring(L, out, bf_len);
		free(out);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "unpack(bf_packed, bf_size) requires a string and an int.");
		return 2;
	}
}

/* Bit numerotation begin with 0 */
int lua_set_bit(lua_State *L)
{
	const char* str;
	char* out;
	size_t len;
	int pos;

	if (lua_isstring(L, 1) && lua_isnumber(L, 2)) {
		str = lua_tolstring(L, 1, &len);
		pos = lua_tonumber(L, 2);
		if (pos < 0 || pos >= len * 8) {
			lua_pushnil(L);
			lua_pushstring(L, "invalid position");
			return 2;
		}
		out = malloc(len);
		memcpy(out, str, len);
		set_bit(out, pos);
		lua_pushlstring(L, out, len);
		free(out);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "set_bit(bf, position) requires a string and an int.");
		return 2;
	}
}

/* Bit numerotation begin with 0 */
int lua_unset_bit(lua_State *L)
{
	const char* str;
	char* out;
	size_t len;
	int pos;

	if (lua_isstring(L, 1) && lua_isnumber(L, 2)) {
		str = lua_tolstring(L, 1, &len);
		pos = lua_tonumber(L, 2);
		if (pos < 0 || pos >= len * 8) {
			lua_pushnil(L);
			lua_pushstring(L, "invalid position");
			return 2;
		}
		out = malloc(len);
		memcpy(out, str, len);
		unset_bit(out, pos);
		lua_pushlstring(L, out, len);
		free(out);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "unset_bit(bf, position) requires a string and an int.");
		return 2;
	}
}

/* Bit numerotation begin with 0 */
int lua_get_bit(lua_State *L)
{
	const char* str;
	size_t len;
	int pos, v;

	if (lua_isstring(L, 1) && lua_isnumber(L, 2)) {
		str = lua_tolstring(L, 1, &len);
		pos = lua_tonumber(L, 2);
		if (pos < 0 || pos >= len * 8) {
			lua_pushnil(L);
			lua_pushstring(L, "invalid position");
			return 2;
		}
		v = get_bit(str, pos);
		lua_pushnumber(L, v);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "unset_bit(bf, position) requires a string and an int.");
		return 2;
	}
}

/* Construct a bloomfilter from an ascii description:
 * "<size_in_bits> <1 position> <1 position> ..."
 * WARNING no ending space (=> will set the bit 0)
 * TODO "<size_in_bits>" => bug
 */
int lua_from_string(lua_State *L)
{
	const char* str;
	char* si;
	char* begin;
	char* out = NULL;
	size_t len;
	int pos, i;
	int size = 0;

	if (lua_isstring(L, 1)) {
		str = lua_tolstring(L, 1, &len);

		si = (char *) str;
		begin = si;
		for (i = 0; i < len; i++) {
			if (!isdigit(*si)) {
				if (size == 0) {
					size = atoi(begin);
					if (size > 128 * 1024 * 1024 || size % 8 != 0) {
						lua_pushnil(L);
						lua_pushstring(L, "max 128kbits (/ 8) bloomfilter");
						return 2;
					}
					out = malloc(size / 8);
					bzero(out, size / 8);
				} else {
					pos = atoi(begin);
					if (pos < 0 || pos >= size) {
						lua_pushnil(L);
						lua_pushstring(L, "invalid position");
						return 2;
					}
					set_bit(out, pos);
				}
				begin = si;
			}
			si++;
		}
		pos = atoi(begin);
		if (pos < 0 || pos >= size) {
			lua_pushnil(L);
			lua_pushstring(L, "invalid position");
			return 2;
		}
		set_bit(out, pos);
		lua_pushlstring(L, out, size / 8);
		free(out);
		return 1;
	} else {
		lua_pushnil(L);
		lua_pushstring(L, "from_string(desc) requires a string.");
		return 2;
	}
}

/*
 * efone - Distributed internet phone system.
 *
 * (c) 1999,2000 Krzysztof Dabrowski
 * (c) 1999,2000 ElysiuM deeZine
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *
 */

/* based on implementation by Finn Yannick Jacobs */

u_int32_t crc_tab[256];

u_int32_t crc32(unsigned char *block, unsigned int length)
{
	register unsigned long crc;
	unsigned long i;
	crc = 0xFFFFFFFF;
	for (i = 0; i < length; i++) {
		crc = ((crc >> 8) & 0x00FFFFFF) ^ crc_tab[(crc ^ *block++) & 0xFF];
	}
	return (crc ^ 0xFFFFFFFF);
}

void crc32gen()
{
	unsigned long crc, poly;
	int i, j;
	poly = 0xEDB88320L;

	for (i = 0; i < 256; i++) {
		crc = i;
		for (j = 8; j > 0; j--) {
			if (crc & 1) {
				crc = (crc >> 1) ^ poly;
			} else {
				crc >>= 1;
			}
		}
		crc_tab[i] = crc;
	}
}

/*
 *   sbloomfilter.c - simple Bloom Filter
 *   (c) Tatsuya Mori <valdzone@gmail.com>
 */
/*

#include "ruby.h"
#include "crc32.h"

static VALUE cBloomFilter;

struct BloomFilter 
{
int m;                  // # of bits in a bloom filter
int k;                  // # of hash functions
int s;                  // seed of hash functions 
unsigned char *ptr;     // bits data 
};

void
bit_set (struct BloomFilter *bf, int index) 
{
int byte_offset = index / 8;
int bit_offset  = index % 8;
unsigned char c = bf->ptr[byte_offset];

c |= (1 << bit_offset);
bf->ptr[byte_offset] = c;
}
int
bit_get (struct BloomFilter *bf, int index) 
{
int byte_offset = index / 8;
int bit_offset  = index % 8;
unsigned char c = bf->ptr[byte_offset];

return (c & (1 << bit_offset)) ? 1 : 0;
}

static VALUE
bf_insert (VALUE self, VALUE key)
{
	int index, seed;
	int i, len, m, k, s;
	char *ckey;

	struct BloomFilter *bf;
	Data_Get_Struct(self, struct BloomFilter, bf);

	Check_Type(key, T_STRING);
	ckey = STR2CSTR(key);
	len = (int) (RSTRING(key)->len); // length of the string in bytes

	m = bf->m;
	k = bf->k;
	s = bf->s;

	for (i=0; i<=k-1; i++) {
		// seeds for hash functions
		seed = i + s;

		// hash
		index = (int)(crc32((unsigned int)(seed), ckey, len) % (unsigned int)(m));  

		//  set a bit at the index
		bit_set(bf, index);                    
	}

	return Qnil;
}

static VALUE
bf_to_s (VALUE self)
{
	struct BloomFilter *bf;
	unsigned char *ptr;
	int i;
	VALUE str;

	Data_Get_Struct(self, struct BloomFilter, bf);
	str = rb_str_new(0, bf->m);

	ptr = (unsigned char *)RSTRING(str)->ptr;
	for(i=0; i<bf->m; i++) 
		*ptr++ = bit_get(bf, i) ? '1' : '0';

	return str;
}

*/
