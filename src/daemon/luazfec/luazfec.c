#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"
#include "fec.c" //NOTE: if we want a standalone lib, use .c. if we want something dependant of zfec, use .h

#define _DEBUG
//#define _SRC_READABLE
#define _SHORT_BYTE_PRINT

//TODO: bind fec_t struct to Lua. For the moment, this will be done inside encode

static int encode(lua_State *L) {

  //retrieves integer variables from stack
  int k = (int)luaL_checknumber(L, 1);
  int m = (int)luaL_checknumber(L, 2);
  int num_block_nums = (int)luaL_checknumber(L, 5);
  int sz = (int)luaL_checknumber(L, 6);
  
  

  //prints integer variables
  #ifdef _DEBUG
  printf("k=%d\n", k);
  printf("m=%d\n", m);
  printf("num_block_nums=%d\n", num_block_nums);
  printf("sz=%d\n", sz);
  #endif

  //creates fec code
  fec_t* fec_ptr_enc = fec_new(k, m);
  
  //initializes i1, i2 for iteration, block_nums as pointer to int, to save the array of int
  int i1, i2, *block_nums;
  //allocates a chunk of memory of size num_block_nums integers
  block_nums = malloc(num_block_nums*sizeof(int));
  //for 1 to num_block_nums
  for (i1 = 1; i1 <= num_block_nums; i1++) {
  	//pushes a number from the table at indx 4 to the top of the stack
  	lua_rawgeti(L, 4, i1);
  	//retrieves the pushed number
    block_nums[i1-1] = (int)luaL_checknumber(L, 6+i1);
    //prints the number
    #ifdef _DEBUG
    printf("block_nums[%d]=%d\n", i1-1, block_nums[i1-1]);
    #endif
  }

  //removes all pushed values
  lua_pop(L, i1-1);

  //initializes src as pointer to pointer to gf, to save the array of strings
  gf **src = malloc(k*sizeof(gf *));
  //for 1 to k
  for (i1 = 1; i1 <= k; i1++) {
  	//pushes a number from the table at indx 3 to the top of the stack
  	lua_rawgeti(L, 3, i1);
  	//retrieves the string
    src[i1-1] = (gf *)lua_tolstring(L, 6+i1, NULL);
    //prints the source
    #ifdef _DEBUG
    #ifdef _SRC_READABLE
    //src is readable
    printf("src[%d]= \"%s\"\n", i1-1, src[i1-1]);
    #else
    //src is not readable; printed byte by byte
    printf("src[%d]= \"", i1-1);
    #ifndef _SHORT_BYTE_PRINT
    for (i2 = 0; i2 < sz; i2++) {
      printf("%d ", src[i1-1][i2]);
    }
    #else
    printf("%d %d %d ... ", (int)((unsigned char *)src[i1-1])[0], (int)((unsigned char *)src[i1-1])[1], (int)((unsigned char *)src[i1-1])[2]);
    printf(" %d %d %d", (int)((unsigned char *)src[i1-1])[sz-3], (int)((unsigned char *)src[i1-1])[sz-2], (int)((unsigned char *)src[i1-1])[sz-1]);
    #endif
    printf("\"\n");
    #endif
    #endif
  }

  //removes all pushed values
  lua_pop(L, i1-1);

  //initializes fecs as pointer to pointer to gf, to save the array of strings, and assigns to it a chunk of num_block_nums pointers to gf
  gf **fecs = malloc((num_block_nums)*sizeof(gf *));
  //for 1 to m
  for (i1 = 0; i1 < num_block_nums; i1++) {
    //each of the pointers gets assigned a chunk of sz unsigned chars
    fecs[i1] = malloc(sz*sizeof(gf));
  }
  
  //encodes
  fec_encode(fec_ptr_enc, (const gf * const restrict* const restrict)src, fecs, block_nums, num_block_nums, sz);

  //creates table on Lua stack
  lua_newtable(L);

  //for 0 to num_block_nums-1
  for (i1 = 0; i1 < num_block_nums; i1++) {
    //prints the string byte by byte
    #ifdef _DEBUG
    printf("fecs[%d]=\"", i1);
    #ifndef _SHORT_BYTE_PRINT
    for (i2 = 0; i2 < sz; i2++) {
      printf("%d ", (int)((unsigned char *)fecs[i1])[i2]);
    }
    #else
    printf("%d %d %d ... ", (int)((unsigned char *)fecs[i1])[0], (int)((unsigned char *)fecs[i1])[1], (int)((unsigned char *)fecs[i1])[2]);
    printf(" %d %d %d", (int)((unsigned char *)fecs[i1])[sz-3], (int)((unsigned char *)fecs[i1])[sz-2], (int)((unsigned char *)fecs[i1])[sz-1]);
    #endif
    printf("\"\n");
    #endif
    //pushes the string
    lua_pushlstring(L, fecs[i1], (size_t)(sz-1));
    //inserts the string in the table
    lua_rawseti(L, 7, i1+1);
  }

  //frees allocated memory
  free(block_nums);
  free(src);
  for (i1 = 0; i1 < num_block_nums; i1++) {
    free(fecs[i1]);
  }
  free(fecs);

  //returns
  return 1;
}

static int decode(lua_State *L) {

  //retrieves integer variables from stack
  int k = (int)luaL_checknumber(L, 1);
  int m = (int)luaL_checknumber(L, 2);
  int num_index = (int)luaL_checknumber(L, 5);
  int sz = (int)luaL_checknumber(L, 6);
  
  //prints integer variables
  #ifdef _DEBUG
  printf("k=%d\n", k);
  printf("m=%d\n", m);
  printf("num_index=%d\n", num_index);
  printf("sz=%d\n", sz);
  #endif

  //creates fec code
  fec_t* fec_ptr_dec = fec_new(k, m);
  
  //initializes i1, i2 for iteration, index as pointer to int, to save the array of int
  int i1, i2, *index;
  //allocates a chunk of memory of size num_index integers
  index = malloc(num_index*sizeof(int));
  //for 1 to num_index
  for (i1 = 1; i1 <= num_index; i1++) {
    //pushes a number from the table at indx 4 to the top of the stack
    lua_rawgeti(L, 4, i1);
    //retrieves the pushed number
    index[i1-1] = (int)luaL_checknumber(L, 6+i1);
    //prints the number
    #ifdef _DEBUG
    printf("index[%d]=%d\n", i1-1, index[i1-1]);
    #endif
  }

  //removes all pushed values
  lua_pop(L, i1-1);

  //initializes inpkts as pointer to pointer to gf, to save the array of strings
  gf **inpkts = malloc(num_index*sizeof(gf *));
  //for 1 to num_index TODO maybe there is a way to extract the size of the array. think of _size
  for (i1 = 1; i1 <= num_index; i1++) {
    //pushes a number from the table at indx 3 to the top of the stack
    lua_rawgeti(L, 3, i1);
    //retrieves the pushed string
    inpkts[i1-1] = (gf *)lua_tolstring(L, 6+i1, NULL);
    //prints the string byte by byte
    #ifdef _DEBUG
    printf("inpkts[%d]= \"", i1-1);
    #ifndef _SHORT_BYTE_PRINT
    for (i2 = 0; i2 < sz; i2++) {
      printf("%d ", (int)((unsigned char *)inpkts[i1-1])[i2]);
    }
    #else
    printf("%d %d %d ... ", (int)((unsigned char *)inpkts[i1-1])[0], (int)((unsigned char *)inpkts[i1-1])[1], (int)((unsigned char *)inpkts[i1-1])[2]);
    printf(" %d %d %d", (int)((unsigned char *)inpkts[i1-1])[sz-3], (int)((unsigned char *)inpkts[i1-1])[sz-2], (int)((unsigned char *)inpkts[i1-1])[sz-1]);
    #endif
    printf("\"\n");
    #endif
  }

  //removes all pushed values
  lua_pop(L, i1-1);

  //initializes outpkts as pointer to pointer to gf, to save the array of strings
  gf **outpkts = malloc(k*sizeof(gf *));
  //for 1 to k
  for (i1 = 0; i1 < k; i1++) {
    //each of the pointers gets assigned a chunk of sz unsigned chars
    outpkts[i1] = malloc(sz*sizeof(gf));
  }

  //decodes
  fec_decode(fec_ptr_dec, (const gf * const restrict* const restrict)inpkts, outpkts, index, sz);

  //creates table on Lua stack
  lua_newtable(L);

  //for 1 to k
  for (i1 = 0; i1 < k; i1++) {
    //prints the string
    #ifdef _DEBUG
    #ifdef _SRC_READABLE
    printf("outpkts[%d]= \"%s\"\n", i1, (unsigned char *)outpkts[i1]);
    #else
    printf("outpkts[%d]= \"", i1);
    #ifndef _SHORT_BYTE_PRINT
    for (i2 = 0; i2 < sz; i2++) {
      printf("%d ", (int)((unsigned char *)outpkts[i1])[i2]);
    }
    #else
    printf("%d %d %d ... ", (int)((unsigned char *)outpkts[i1])[0], (int)((unsigned char *)outpkts[i1])[1], (int)((unsigned char *)outpkts[i1])[2]);
    printf(" %d %d %d", (int)((unsigned char *)outpkts[i1])[sz-3], (int)((unsigned char *)outpkts[i1])[sz-2], (int)((unsigned char *)outpkts[i1])[sz-1]);
    #endif
    printf("\"\n");
    #endif
    #endif
    //pushes the string
    lua_pushlstring(L, outpkts[i1], (size_t)(sz-1));
    //inserts the string in the table
    lua_rawseti(L, 7, i1+1);
  }
  
  //frees allocated memory
  free(inpkts);
  free(index);
  for (i1 = 0; i1 < k; i1++) {
    free(outpkts[i1]);
  }
  free(outpkts);

  //returns
  return 1;
}

//declaration of the 2 functions
static const luaL_reg luazfec[] = {
{"encode",   encode},
{"decode",   decode},
{NULL, NULL}
};

/*
** Open luazfec library
*/
LUALIB_API int luaopen_luazfec(lua_State *L) {
  //registers the functions
  luaL_register(L, "luazfec", luazfec);
  //registers constants. Not used for the moment
  lua_pushboolean(L, 0);
  lua_setfield(L, -2, "debug");
  //lua_pushnumber(L, HUGE_VAL);
  //lua_setfield(L, -2, "huge");
  return 1;
}