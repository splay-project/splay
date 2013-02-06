/*
    FUSE: Filesystem in Userspace lua binding
    Copyright 2007 (C) gary ng <linux@garyng.com>

    This program can be distributed under the terms of the GNU LGPL.
*/


#define _GNU_SOURCE

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#ifdef HAVE_SETXATTR
#include <sys/xattr.h>
#endif

#include <pthread.h>

#include <signal.h>

#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

#ifndef FALSE
#define FALSE 0
#define TRUE !FALSE
#endif

static pthread_rwlock_t vm_lock;
static lua_State *L_VM = NULL;
static int dispatch_table = LUA_REFNIL;
static int pulse_freq = 5;

#define min(x,y) (x > y ? y : x)
    
#define LOAD_FUNC(x)    \
    pthread_rwlock_wrlock(&vm_lock);\
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, dispatch_table); \
    lua_pushstring(L_VM, (x));\
    lua_gettable(L_VM, -2);\
    if (!lua_isfunction(L_VM, -1)) {\
        fprintf(stderr,"load function %s failed\n", x);\
        lua_pop(L_VM, 2);\
        pthread_rwlock_unlock(&vm_lock);\
        return -ENOSYS;\
    }\
    lua_pushvalue(L_VM, -2);\

#define EPILOGUE(x) \
    pthread_rwlock_unlock(&vm_lock);\
    lua_pop(L_VM, x+1);\
    
#define obj_pcall(x, y, z) \
    res = lua_pcall(L_VM, x+1, y, z);\

#define err_pcall(x) \
    if (x) {\
        const char *err_msg = lua_tostring(L_VM, -1);\
        fprintf(stderr, "%s\n", err_msg);\
        EPILOGUE(1)\
        return -1;\
    }\

static void l_signal(int i)
{						/* assert(i==SIGALRM); */

    int res;
     
    signal(i,SIG_DFL); /* reset */

    LOAD_FUNC("pulse")
    obj_pcall(0, 1, 0);
    err_pcall(res);
    EPILOGUE(1)
}

static int xmp_getattr(const char *path, struct stat *st)
{
    int res;

    LOAD_FUNC("getattr")
    lua_pushstring(L_VM, path);
    obj_pcall(1, 11, 0);
    err_pcall(res);

    res = lua_tointeger(L_VM, -11);

    st->st_mode = lua_tointeger(L_VM, -10);
    st->st_ino  = lua_tointeger(L_VM, -9);
    st->st_rdev = lua_tointeger(L_VM, -8);
    st->st_dev  = lua_tointeger(L_VM, -8);
    st->st_nlink= lua_tointeger(L_VM, -7);
    st->st_uid  = lua_tointeger(L_VM, -6);
    st->st_gid  = lua_tointeger(L_VM, -5);
    st->st_size = lua_tointeger(L_VM, -4);
    st->st_atime= lua_tointeger(L_VM, -3);
    st->st_mtime= lua_tointeger(L_VM, -2);
    st->st_ctime= lua_tointeger(L_VM, -1);

    /* Fill in fields not provided by Python lstat() */
    st->st_blksize= 4096;
    st->st_blocks= (st->st_size + 511)/512;

    EPILOGUE(11)

    return res;
}

static int xmp_fgetattr(const char *path, struct stat *st,
                        struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("fgetattr")
    lua_pushstring(L_VM, path);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 

    obj_pcall(2, 11, 0);
    err_pcall(res);

    res = lua_tointeger(L_VM, -11);

    st->st_mode = lua_tointeger(L_VM, -10);
    st->st_ino  = lua_tointeger(L_VM, -9);
    st->st_rdev = lua_tointeger(L_VM, -8);
    st->st_dev  = lua_tointeger(L_VM, -8);
    st->st_nlink= lua_tointeger(L_VM, -7);
    st->st_uid  = lua_tointeger(L_VM, -6);
    st->st_gid  = lua_tointeger(L_VM, -5);
    st->st_size = lua_tointeger(L_VM, -4);
    st->st_atime= lua_tointeger(L_VM, -3);
    st->st_mtime= lua_tointeger(L_VM, -2);
    st->st_ctime= lua_tointeger(L_VM, -1);

    /* Fill in fields not provided by Python lstat() */
    st->st_blksize= 4096;
    st->st_blocks= (st->st_size + 511)/512;

    EPILOGUE(11);

    return res;
}

static int xmp_access(const char *path, int mask)
{
    int res;

    LOAD_FUNC("access")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, mask);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_readlink(const char *path, char *buf, size_t size)
{
    int res;
    size_t l;
    const char *str;

    LOAD_FUNC("readlink")
    lua_pushstring(L_VM, path);
    obj_pcall(1, 2, 0);
    err_pcall(res);

    res = lua_tointeger(L_VM, -2);
    str = lua_tolstring(L_VM, -1, &l);
    memcpy(buf, str, min(l,size-1));
    buf[min(l,size-1)]='\0';

    EPILOGUE(2);

    return res;
}

static int xmp_opendir(const char *path, struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("opendir")
    lua_pushstring(L_VM, path);
    obj_pcall(1, 2, 0);
    err_pcall(res);

    res = lua_tointeger(L_VM, -2);

    /* save the return as reference */
    fi->fh = luaL_ref(L_VM, LUA_REGISTRYINDEX);

    EPILOGUE(1);

    return res;
}

static inline DIR *get_dirp(struct fuse_file_info *fi)
{
    return (DIR *) (uintptr_t) fi->fh;
}

static int xmp_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                       off_t offset, struct fuse_file_info *fi)
{
    int res;
    struct dirent *de;
    int cnt;
    int done = FALSE;
    int i;

    LOAD_FUNC("readdir")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, offset);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(3, 2, 0);
    err_pcall(res);

    res = lua_tointeger(L_VM, -2);
    cnt = lua_objlen(L_VM, -1);

    for (i =0; i < cnt && !done; i++) {
        struct stat st;
        off_t o = 0;
        const char *name = NULL;


        lua_rawgeti(L_VM, -1, i+1);

        if (lua_istable(L_VM, -1)) {

            memset(&st, 0, sizeof(st));

            lua_pushstring(L_VM, "ino");
            lua_gettable(L_VM, -2);
            st.st_ino = lua_tointeger(L_VM, -1);

            lua_pushstring(L_VM, "d_type");
            lua_gettable(L_VM, -3);
            st.st_mode = lua_tointeger(L_VM, -1);

            lua_pushstring(L_VM, "offset");
            lua_gettable(L_VM, -4);
            o = lua_tointeger(L_VM, -1);

            lua_pushstring(L_VM, "d_name");
            lua_gettable(L_VM, -5);
            name = lua_tostring(L_VM, -1); 

            if (!name || filler(buf, name, &st, o)) done = TRUE;

            lua_pop(L_VM, 5);

        } else if (lua_isstring(L_VM, -1)) {  
            name = lua_tostring(L_VM, -1);
            if (!name || filler(buf, name, NULL, 0)) done = TRUE;
            lua_pop(L_VM, 1);
        } else {
            lua_pop(L_VM, 1);
        }
    }

    EPILOGUE(2);

    return res;
}

static int xmp_fsyncdir(const char *path, int isdatasync, struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("syncdir")
    lua_pushstring(L_VM, path);
    lua_pushboolean(L_VM, isdatasync);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(3, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);
    return res;
}

static int xmp_releasedir(const char *path, struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("releasedir")
    lua_pushstring(L_VM, path);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(2, 1, 0);
    luaL_unref(L_VM, LUA_REGISTRYINDEX, fi->fh);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);
    return res;
}

static int xmp_mknod(const char *path, mode_t mode, dev_t rdev)
{
    int res;
    int fifo = S_ISFIFO(mode);

    LOAD_FUNC("mknod")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, mode);
    lua_pushnumber(L_VM, rdev);
    obj_pcall(3, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);

    EPILOGUE(1);

    return res;
}

static int xmp_mkdir(const char *path, mode_t mode)
{
    int res;

    LOAD_FUNC("mkdir")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, mode);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);

    EPILOGUE(1);

    return res;
}

static int xmp_unlink(const char *path)
{
    int res;

    LOAD_FUNC("unlink")
    lua_pushstring(L_VM, path);
    obj_pcall(1, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_rmdir(const char *path)
{
    int res;

    LOAD_FUNC("rmdir")
    lua_pushstring(L_VM, path);
    obj_pcall(1, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);
    
    return res;
}

static int xmp_symlink(const char *from, const char *to)
{
    int res;

    LOAD_FUNC("symlink")
    lua_pushstring(L_VM, from);
    lua_pushstring(L_VM, to);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_rename(const char *from, const char *to)
{
    int res;

    LOAD_FUNC("rename")
    lua_pushstring(L_VM, from);
    lua_pushstring(L_VM, to);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_link(const char *from, const char *to)
{
    int res;

    LOAD_FUNC("link")
    lua_pushstring(L_VM, from);
    lua_pushstring(L_VM, to);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_chmod(const char *path, mode_t mode)
{
    int res;

    LOAD_FUNC("chmod")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, mode);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_chown(const char *path, uid_t uid, gid_t gid)
{
    int res;

    LOAD_FUNC("chown")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, uid);
    lua_pushnumber(L_VM, gid);
    obj_pcall(3, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_truncate(const char *path, off_t size)
{
    int res;

    LOAD_FUNC("truncate")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, size);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_ftruncate(const char *path, off_t size,
                         struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("ftruncate")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, size);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(3, 2, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -2);
    fi->fh = luaL_ref(L_VM, LUA_REGISTRYINDEX);
    EPILOGUE(1);

    return res;
}

static int xmp_utime(const char *path, struct utimbuf *buf)
{
    int res;

    LOAD_FUNC("utime")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, buf->actime);
    lua_pushnumber(L_VM, buf->modtime);
    obj_pcall(3, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_create(const char *path, mode_t mode, struct fuse_file_info *fi)
{
    int res;
    int fd;

    LOAD_FUNC("create")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, mode);
    lua_pushnumber(L_VM, fi->flags);
    obj_pcall(3, 2, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -2);
    fi->fh = luaL_ref(L_VM, LUA_REGISTRYINDEX);
    EPILOGUE(1);

    return res;
}

static int xmp_open(const char *path, struct fuse_file_info *fi)
{
    int res;
    int fd;

    LOAD_FUNC("open")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, fi->flags);
    obj_pcall(2, 2, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -2);
    fi->fh = luaL_ref(L_VM, LUA_REGISTRYINDEX);
    EPILOGUE(1);

    return res;
}

static int xmp_read(const char *path, char *buf, size_t size, off_t offset,
                    struct fuse_file_info *fi)
{
    int res;
    const char* o;
    size_t l;

    LOAD_FUNC("read")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, size);
    lua_pushnumber(L_VM, offset);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(4, 2, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -2);
    o = lua_tolstring(L_VM, -1, &l);
    if (o) memcpy(buf, o, min(l,size));
    EPILOGUE(2)

    return o ? min(l,size) : res;
}

static int xmp_write(const char *path, const char *buf, size_t size,
                     off_t offset, struct fuse_file_info *fi)
{
    int res;
    int written;

    LOAD_FUNC("write")
    lua_pushstring(L_VM, path);
    lua_pushlstring(L_VM, buf, size);
    lua_pushnumber(L_VM, offset);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(4, 2, 0);
    err_pcall(res);
    written = lua_tointeger(L_VM, -2);
    fi->fh = luaL_ref(L_VM, LUA_REGISTRYINDEX);
    EPILOGUE(1)

    return written;
}

static int xmp_statfs(const char *path, struct statvfs *st)
{
    int res;

    LOAD_FUNC("statfs")
    lua_pushstring(L_VM, path);
    obj_pcall(1, 7, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -7);
    st->f_bsize = lua_tointeger(L_VM, -6);
    st->f_blocks = lua_tointeger(L_VM, -5);
    st->f_bfree  = lua_tointeger(L_VM, -4);
    st->f_bavail = lua_tointeger(L_VM, -3);
    st->f_files  = lua_tointeger(L_VM, -2);
    st->f_ffree  = lua_tointeger(L_VM, -1);

    EPILOGUE(7);

    return res;
}

static int xmp_flush(const char *path, struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("flush")
    lua_pushstring(L_VM, path);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_release(const char *path, struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("release")
    lua_pushstring(L_VM, path);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    luaL_unref(L_VM, LUA_REGISTRYINDEX, fi->fh);
    EPILOGUE(1);

    return res;
}

static int xmp_fsync(const char *path, int isdatasync,
                     struct fuse_file_info *fi)
{
    int res;

    LOAD_FUNC("fsync")
    lua_pushstring(L_VM, path);
    lua_pushboolean(L_VM, isdatasync);
    lua_rawgeti(L_VM, LUA_REGISTRYINDEX, fi->fh); 
    obj_pcall(3, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

#ifdef HAVE_SETXATTR
/* xattr operations are optional and can safely be left unimplemented */
static int xmp_setxattr(const char *path, const char *name, const char *value,
                        size_t size, int flags)
{
    int res;

    LOAD_FUNC("setxattr")
    lua_pushstring(L_VM, path);
    lua_pushstring(L_VM, name);
    lua_pushlstring(L_VM, value, size);
    lua_pushnumber(L_VM, flags);
    obj_pcall(4, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}

static int xmp_getxattr(const char *path, const char *name, char *value,
                    size_t size)
{
    int res;
    size_t l;
    const char *o;

    LOAD_FUNC("getxattr")
    lua_pushstring(L_VM, path);
    lua_pushstring(L_VM, name);
    lua_pushnumber(L_VM, size);
    obj_pcall(3, 2, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -2);
    o = lua_tolstring(L_VM, -1, &l);
    if (o) memcpy(value, o, min(l,size));
    EPILOGUE(2);

    return o ? (size > 0  ? min(l,size) : l) : res;
}

static int xmp_listxattr(const char *path, char *list, size_t size)
{
    int res;
    size_t l;
    const char *o;

    LOAD_FUNC("listxattr")
    lua_pushstring(L_VM, path);
    lua_pushnumber(L_VM, size);
    obj_pcall(2, 2, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -2);
    o = lua_tolstring(L_VM, -1, &l);
    if (o) memcpy(list, o, min(l,size));
    EPILOGUE(2);

    return o ? (size > 0  ? min(l,size) : l) : res;
}

static int xmp_removexattr(const char *path, const char *name)
{
    int res;

    LOAD_FUNC("removexattr")
    lua_pushstring(L_VM, path);
    lua_pushstring(L_VM, name);
    obj_pcall(2, 1, 0);
    err_pcall(res);
    res = lua_tointeger(L_VM, -1);
    EPILOGUE(1);

    return res;
}
#endif /* HAVE_SETXATTR */

static struct fuse_operations xmp_oper = {
    .getattr	= xmp_getattr,
    .fgetattr	= xmp_fgetattr,
    .access	= xmp_access,
    .readlink	= xmp_readlink,
    .readdir	= xmp_readdir,
    .opendir	= xmp_opendir,
    .fsyncdir    = xmp_fsyncdir,
    .releasedir	= xmp_releasedir,
#if 0
#endif
    .mknod	= xmp_mknod,
    .mkdir	= xmp_mkdir,
    .symlink	= xmp_symlink,
    .unlink	= xmp_unlink,
    .rmdir	= xmp_rmdir,
    .rename	= xmp_rename,
    .link	= xmp_link,
    .chmod	= xmp_chmod,
    .chown	= xmp_chown,
    .truncate	= xmp_truncate,
    .ftruncate	= xmp_ftruncate,
    .utime	= xmp_utime,
    .create	= xmp_create,
    .open	= xmp_open,
    .read	= xmp_read,
    .write	= xmp_write,
    .statfs	= xmp_statfs,
    .release	= xmp_release,
    .flush	= xmp_flush,
    .fsync	= xmp_fsync,
#ifdef HAVE_SETXATTR
    .setxattr	= xmp_setxattr,
    .getxattr	= xmp_getxattr,
    .listxattr	= xmp_listxattr,
    .removexattr= xmp_removexattr,
#endif
};

static xmp_alarm(lua_State *L)
{
    
    int freq = lua_tointeger(L, -1);
    signal(SIGALRM,l_signal);
    alarm(freq);
    return 0;
}

static xmp_main(lua_State *L)
{
    /*
     * called in lua as fuse.main(dispatch_table, fuse_table)
     */

    L_VM = L;
    int argc = lua_objlen(L, 2);
    char *argv[256];
    int i;
    
    if (argc < 2) luaL_error(L, "check parameter fusemount parameter table");

    #if 0
    lua_pushstring(L, "pulse_freq");
    lua_gettable(L, 1);
    pulse_freq = lua_tointeger(L,-1);
    lua_pop(L,1);
    if (pulse_freq == 0) pulse_freq = 10;
    #endif

    /*
     * save dispatch table for future reference by C program
     */
    lua_pushvalue(L, 1);
    dispatch_table = luaL_ref(L_VM, LUA_REGISTRYINDEX);

    /*
     * turn fuse option table(effectively cmdline) to argv style
     */
    for (i=0; i < argc && i < 255; i++) {
        lua_rawgeti(L, 2, i + 1);
        argv[i]=lua_tostring(L, -1); 
    }
    argv[i] = NULL;

#if 0
    if (pulse_freq > 0) {
        signal(SIGALRM,l_signal);
        alarm(pulse_freq);
    }
#endif
    
    /*
     * hand over to fuse loop
     */

    fuse_main(argc, argv, &xmp_oper);

    /*
     * remove argv strings from L stack
     */
    lua_pop(L, i);
    
    /*
     * discard reference to dispatch_table
     */
    luaL_unref(L, LUA_REGISTRYINDEX, dispatch_table);

    #if 0
    signal(SIGALRM, SIG_DFL);
    #endif

    return 0;
}

static int xmp_get_context(lua_State *L)
{
	struct fuse_context *fc;
	fc = fuse_get_context();
    lua_pushnumber(L, fc->uid);
    lua_pushnumber(L, fc->gid);
    lua_pushnumber(L, fc->pid);
    lua_pushnumber(L, geteuid());
    lua_pushnumber(L, getegid());

    return 5;
}

static const luaL_reg Rm[] = {
	{ "main",	xmp_main},
	{ "alarm",	xmp_alarm},
	{ "context",xmp_get_context},
	{ NULL,		NULL	}
};

LUA_API int luaopen_fuse(lua_State *L)
{
	luaL_openlib( L, "fuse", Rm, 0 );

	lua_pushliteral (L, "_COPYRIGHT");
	lua_pushliteral (L, "Copyright (C) 2007 gary ng <linux@garyng.com>");
	lua_settable (L, -3);
	lua_pushliteral (L, "_DESCRIPTION");
	lua_pushliteral (L, "Binding to linux fuse file system");
	lua_settable (L, -3);
	lua_pushliteral (L, "_VERSION");
	lua_pushliteral (L, "LuaFuse 0.1");
	lua_settable (L, -3);

    pthread_rwlock_init(&vm_lock, NULL);
    return 1;
}
