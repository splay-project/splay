#!/usr/bin/env lua
--[[
    Memory FS in FUSE using the lua binding
    Copyright 2007 (C) gary ng <linux@garyng.com>

    This program can be distributed under the terms of the GNU LGPL.
]]

local fuse = require 'fuse'
local dbclient = require 'distdb-client'
local serializer = require'splay.lbinenc'
local crypto = require'crypto'
local misc = require'splay.misc'
--require'profiler'

local S_WID = 1 --world
local S_GID = 2^3 --group
local S_UID = 2^6 --owner
local S_SID = 2^9 --sticky bits etc.
local S_IFIFO = 1*2^12
local S_IFCHR = 2*2^12
local S_IFDIR = 4*2^12
local S_IFBLK = 6*2^12
local S_IFREG = 2^15
local S_IFLNK = S_IFREG + S_IFCHR
local ENOENT = -2
local ENOSYS = -38
local ENOATTR = -516
local ENOTSUPP = -524

local block_size = 256*1024
local blank_block=("0"):rep(block_size)
local open_mode={'rb','wb','rb+'}
local log_domains = {
    MAIN_OP=true,
    DB_OP=true,
    FILE_INODE_OP=true,
    DIR_OP=true,
    LINK_OP=true,
    READ_WRITE_OP=true,
    FILE_MISC_OP=true,
    MV_CP_OP=true
}

local consistency_type = "consistent"

local to_report_t = {}

local db_port = 14407

--function reportlog: function created to send messages to a single log file; it handles different log domains, like DB_OP (Database Operation), etc.
function reportlog(log_domain, message, args)
    --if logging in the proposed log domain is ON
    if log_domains[log_domain] then
        --opens the log file
        local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")
        --writes the message with a timestamp
        logfile1:write(misc.time()..": "..message.."\n")
        --writes the table of arguments
        logfile1:write(print_tablez("args", 0, args))
        --writes a new line
        logfile1:write("\n")
        --closes the file
        logfile1:close()
    end
end

function fast_reportlog(message)
    --opens the log file
    local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log2.txt","a")
    --writes the message with a timestamp
    logfile1:write(message)
    --closes the file
    logfile1:close()
end

function reportlog_screen(log_domain, message, args)
    --if logging in the proposed log domain is ON
    if log_domains[log_domain] then
        --writes the message with a timestamp
        print(misc.time()..": "..message)
        --writes the table of arguments
        print(print_tablez("args", 0, args))
    end
end

--function write_in_db: writes an element into the underlying DB
local function write_in_db(unhashed_key, value)
    --creates the DB Key by SHA1-ing the concatenation of the type of element and the unhashed key (e.g. the filename, the inode number)
    local db_key = crypto.evp.digest("sha1", unhashed_key)
    --logs
    --reportlog("DB_OP", "write_in_db: about to write in distdb, unhashed_key="..unhashed_key..", db_key="..db_key, {value=value})
    --sends the value
    return send_put(db_port, consistency_type, db_key, value)
end

--function read_from_db: reads an element from the underlying DB
local function read_from_db(unhashed_key)
    --creates the DB Key by SHA1-ing the concatenation of the type of element and the unhashed key (e.g. the filename, the inode number)
    local db_key = crypto.evp.digest("sha1", unhashed_key)
    --logs
    --reportlog("DB_OP", "read_from_db: about to read from distdb, unhashed_key="..unhashed_key..", db_key="..db_key,{})
    --sends a GET command to the DB
    return send_get(db_port, consistency_type, db_key)
end

--function read_from_db: reads an element from the underlying DB
local function delete_from_db(unhashed_key)
    --creates the DB Key by SHA1-ing the concatenation of the type of element and the unhashed key (e.g. the filename, the inode number)
    local db_key = crypto.evp.digest("sha1", unhashed_key)
    --logs
    --reportlog("DB_OP", "delete_from_db: about to delete from distdb, unhashed_key="..unhashed_key..", db_key="..db_key,{})
    --sends a GET command to the DB
    return send_delete(db_port, consistency_type, db_key)
end

--function splitfilename: splits the filename in base and dir; for example: "/usr/include/lua/5.1/lua.h" -> "/usr/include/lua/5.1", "lua.h"
function string:splitfilename() 
    local dir,file = self:match("(.-)([^:/\\]*)$")
    local dirmatch = dir:match("(.-)[/\\]?$")
    --if the base is "/" don't do anything, return it like this
    if dir == "/" then
        return dir, file
    --if not, it will be something like "/usr/include/lua/5.1/", so remove the trialing "/"
    else
        return dir:match("(.-)[/\\]?$"), file
    end
end


--bit logic used for the mode field. TODO replace the mode field in file's metadata with a table (if I have the time, it's not really necessary)
local tab = {  -- tab[i+1][j+1] = xor(i, j) where i,j in (0-15)
  {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, },
  {1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14, },

  {2, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13, },
  {3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12, },
  {4, 5, 6, 7, 0, 1, 2, 3, 12, 13, 14, 15, 8, 9, 10, 11, },
  {5, 4, 7, 6, 1, 0, 3, 2, 13, 12, 15, 14, 9, 8, 11, 10, },
  {6, 7, 4, 5, 2, 3, 0, 1, 14, 15, 12, 13, 10, 11, 8, 9, },
  {7, 6, 5, 4, 3, 2, 1, 0, 15, 14, 13, 12, 11, 10, 9, 8, },
  {8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7, },
  {9, 8, 11, 10, 13, 12, 15, 14, 1, 0, 3, 2, 5, 4, 7, 6, },
  {10, 11, 8, 9, 14, 15, 12, 13, 2, 3, 0, 1, 6, 7, 4, 5, },
  {11, 10, 9, 8, 15, 14, 13, 12, 3, 2, 1, 0, 7, 6, 5, 4, },
  {12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3, },
  {13, 12, 15, 14, 9, 8, 11, 10, 5, 4, 7, 6, 1, 0, 3, 2, },
  {14, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3, 0, 1, },
  {15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, },
}

local function _bxor (a,b)
    local res, c = 0, 1
    while a > 0 and b > 0 do
        local a2, b2 = a % 16, b % 16
        res = res + tab[a2+1][b2+1]*c
        a = (a-a2)/16
        b = (b-b2)/16
        c = c*16
    end
    res = res + a*c + b*c
    return res
end


local ff = 2^32 - 1
local function _bnot(a) return ff - a end

local function _band(a,b) return ((a+b) - _bxor(a,b))/2 end

local function _bor(a,b) return ff - _band(ff - a, ff - b) end

local function set_bits(mode, bits)
    return _bor(mode, bits)
end

local function is_dir(mode)
    local o = ((mode - mode % S_IFDIR)/S_IFDIR) % 2
    return o ~= 0
end

--function decode_acl: TODO check what this does in memfs.lua
local function decode_acl(s)

    reportlog("FILE_INODE_OP", "decode_acl: ENTERED", {})
    --reportlog("FILE_INODE_OP", "decode_acl: ENTERED for s="..s, {})

    local version = s:sub(1,4)
    local n = 5
    while true do
        local tag = s:sub(n, n + 1)
        local perm = s:sub(n + 2, n + 3)
        local id = s:sub(n + 4, n + 7)
        n = n + 8
        if n >= #s then break end
    end
end


--function mk_mode: creates the mode from the owner, group, world rights and the sticky bit
function mk_mode(owner, group, world, sticky)
    --logs entrance
    reportlog("FILE_INODE_OP", "mk_mode: ENTERED", {})
    --reportlog("FILE_INODE_OP", "mk_mode: ENTERED for owner="..owner..", group="..group..", world="..world, {sticky=sticky})

    sticky = sticky or 0
    local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID
    --reportlog("_OP", "mk_mode returns result_mode="..result_mode, {})
    return result_mode
end

--function get_block: gets a block from the db
function get_block(block_n)
    --safety if: if the block_n is not a number, return with error
    if type(block_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "get_block: ERROR, block_n not a number", {})
        return nil
    end
    --logs entrance
    reportlog("FILE_INODE_OP", "get_block: ENTERED", {})
    --reportlog("FILE_INODE_OP", "get_block: ENTERED for block_n="..block_n, {})
    --reads the file element from the DB
    local ok_read_from_db_block, data = read_from_db("block:"..block_n)
    --if the reading was not successful, report the error and return nil
    if not ok_read_from_db_block then
        --reportlog("FILE_INODE_OP", "get_block: ERROR, read_from_db of block was not OK", {})
        return nil
    end
    --if everything went well return the inode number
    return data
end

--function get_inode: gets a inode element from the db
function get_inode(inode_n)
    --logs entrance
    --reportlog("FILE_INODE_OP", "get_inode: ENTERED", {})
    reportlog("FILE_INODE_OP", "get_inode: ENTERED for inode_n=", {inode_n=inode_n})
    
    --safety if: if the inode_n is not a number, return with error
    if type(inode_n) ~= "number" then
        reportlog("FILE_INODE_OP", "get_inode: ERROR, inode_n not a number", {})
        return nil
    end
    --reads the inode element from the DB
    local ok_read_from_db_inode, inode_serialized = read_from_db("inode:"..inode_n)
    reportlog("FILE_INODE_OP", "get_inode: read_from_db returned", {ok_read_from_db_inode=ok_read_from_db_inode, inode_serialized=inode_serialized})

    --if the reading was not successful, report the error and return nil
    if not ok_read_from_db_inode then
        reportlog("FILE_INODE_OP", "get_inode: ERROR, read_from_db of inode was not OK", {})
        return nil
    end

    --if the reading was not successful, report the error and return nil
    if not inode_serialized then
        reportlog("FILE_INODE_OP", "get_inode: inode is nil, returning nil", {})
        return nil
    end

    reportlog("FILE_INODE_OP", "get_inode: trying to serializer_decode, type of inode_serialized="..type(inode_serialized), {})

    local inode = serializer.decode(inode_serialized)

    reportlog("FILE_INODE_OP", "get_inode: read_from_db returned", {inode=inode})
    
    --if everything went well return the inode
    return inode
end

--function get_inode_n: gets a inode number from the db, by identifying it with the filename
function get_inode_n(filename)
    --logs entrance
    --reportlog("FILE_INODE_OP", "get_inode_n: ENTERED", {})
    reportlog("FILE_INODE_OP", "get_inode_n: ENTERED for filename="..filename, {})
    --reads the file element from the DB
    local ok_read_from_db_file, inode_n = read_from_db("file:"..filename)
    --if the reading was not successful, report the error and return nil
    if not ok_read_from_db_file then
        reportlog("FILE_INODE_OP", "get_inode_n: ERROR, read_from_db of file was not OK", {})
        return nil
    end
    --if everything went well return the inode number
    return tonumber(inode_n)
end

--function get_inode_from_filename: gets a inode element from the db, by identifying it with the filename
function get_inode_from_filename(filename)
    --logs entrance
    reportlog("FILE_INODE_OP", "get_inode_from_filename: ENTERED", {})
    --reportlog("FILE_INODE_OP", "get_inode_from_filename: ENTERED for filename="..filename, {})
    --the inode number is extracted by calling get_inode_n
    local inode_n = get_inode_n(filename)

    reportlog("FILE_INODE_OP", "get_inode_from_filename: inode number retrieved", {inode_n=inode_n})

    --returns the corresponding inode
    return get_inode(inode_n)
end

--function put_block: puts a block element into the db
function put_block(block_n, data)
    --if block_n is not a number, report an error and return nil
    if type(block_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "put_block: ERROR, block_n not a number", {})
        return nil
    end
    --if data is not a string, report an error and return nil
    if type(data) ~= "string" then
        --reportlog("FILE_INODE_OP", "put_block: ERROR, data not a string", {})
        return nil
    end
    
    --logs entrance
    reportlog("FILE_INODE_OP", "put_block: ENTERED", {})
    --reportlog("FILE_INODE_OP", "put_block: ENTERED for block_n="..block_n..", data size="..string.len(data), {})
    --writes the block in the DB
    local ok_write_in_db_block = write_in_db("block:"..block_n, data)
    --if the writing was not successful, report the error and return nil
    if not ok_write_in_db_block then
        --reportlog("FILE_INODE_OP", "put_block: ERROR, write_in_db of block was not OK", {})
        return nil
    end
    --if everything went well return true
    return true
end

--function put_inode: puts a inode element into the db
function put_inode(inode_n, inode)
    --logs entrance
    reportlog("FILE_INODE_OP", "put_inode: ENTERED", {})
    --reportlog("FILE_INODE_OP", "put_inode: ENTERED for inode_n="..inode_n, {inode=inode})
    --if inode_n is not a number, report an error and return nil
    if type(inode_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "put_inode: ERROR, inode_n not a number", {})
        return nil
    end
    --if inode is not a table, report an error and return nil
    if type(inode) ~= "table" then
        --reportlog("FILE_INODE_OP", "put_inode: ERROR, inode not a table", {})
        return nil
    end    
    --writes the inode in the DB
    local ok_write_in_db_inode = write_in_db("inode:"..inode_n, serializer.encode(inode))
    --if the writing was not successful, report the error and return nil
    if not ok_write_in_db_inode then
        --reportlog("FILE_INODE_OP", "put_inode: ERROR, write_in_db of inode was not OK", {})
        return nil
    end
    --if everything went well return true
    return true
end

--function put_file: puts a file element into the db
function put_file(filename, inode_n)
    --if filename is not a string, report an error and return nil
    if type(filename) ~= "string" then
        --reportlog("FILE_INODE_OP", "put_file: ERROR, filename not a string", {})
        return nil
    end

    --logs entrance
    reportlog("FILE_INODE_OP", "put_file: ENTERED", {})
    --reportlog("FILE_INODE_OP", "put_file: ENTERED for filename="..filename..", inode_n="..inode_n, {})
    --if inode_n is not a number, report an error and return nil
    if type(inode_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "put_file: ERROR, inode_n not a number", {})
        return nil
    end
    --writes the file in the DB
    local ok_write_in_db_file = write_in_db("file:"..filename, inode_n)
    --if the writing was not successful, report the error and return nil
    if not ok_write_in_db_file then
        --reportlog("FILE_INODE_OP", "put_file: ERROR, write_in_db of file was not OK", {})
        return nil
    end
    --if everything went well return true
    return true
end

function delete_block(block_n)

    if type(block_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "delete_block: ERROR, block_n not a number", {})
        return nil
    end

    --logs entrance
    reportlog("FILE_INODE_OP", "delete_block: ENTERED", {})
    --reportlog("FILE_INODE_OP", "delete_block: ENTERED for block_n="..block_n, {})
    
    local ok_delete_from_db_block = delete_from_db("block:"..block_n)

    if not ok_delete_from_db_block then
        --reportlog("FILE_INODE_OP", "delete_block: ERROR, delete_from_db of inode was not OK", {})
        return nil
    end

    return true
end

function delete_inode(inode_n)
--TODOS: WEIRD LATENCY IN DELETE_LOCAL
--I THINK THE INODE DOES NOT GET DELETED.
    if type(inode_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "delete_inode: ERROR, inode_n not a number", {})
        return nil
    end

    --logs entrance
    reportlog("FILE_INODE_OP", "delete_inode: ENTERED", {})
    --reportlog("FILE_INODE_OP", "delete_inode: ENTERED for inode_n="..inode_n, {})
    
    --[[
    for i,v in ipairs(inode.content) do
        delete_from_db("block:"..v) --TODO: NOT CHECKING IF SUCCESSFUL
    end
    --]]

    
    local ok_delete_from_db_inode = delete_from_db("inode:"..inode_n)

    if not ok_delete_from_db_inode then
        --reportlog("_OP", "delete_inode: ERROR, delete_from_db of inode was not OK", {})
        return nil
    end
    
    return true
end

function delete_dir_inode(inode_n)
    --logs entrance
    reportlog("FILE_INODE_OP", "delete_dir_inode: ENTERED", {})
    --reportlog("FILE_INODE_OP", "delete_dir_inode: ENTERED for inode_n="..inode_n, {})
    
    if type(inode_n) ~= "number" then
        --reportlog("FILE_INODE_OP", "delete_inode: ERROR, inode_n not a number", {})
        return nil
    end

    
    local ok_delete_from_db_inode = delete_from_db("inode:"..inode_n)

    if not ok_delete_from_db_inode then
        --reportlog("_OP", "delete_dir_inode: ERROR, delete_from_db of inode was not OK", {})
        return nil
    end

    return true
end

function delete_file(filename)

    if type(filename) ~= "string" then
        --reportlog("FILE_INODE_OP", "delete_file: ERROR, filename not a string", {})
        return nil
    end

    --logs entrance
    reportlog("FILE_INODE_OP", "delete_file: ENTERED", {})
    --reportlog("FILE_INODE_OP", "delete_file: ENTERED for filename="..filename, {})
    
    local ok_delete_from_db_file = delete_from_db("file:"..filename)

    if not ok_delete_from_db_file then
        --reportlog("FILE_INODE_OP", "delete_file: ERROR, delete_from_db of inode was not OK", {})
        return nil
    end

    return true
end


function get_attributes(filename)
    --logs entrance
    reportlog("FILE_MISC_OP", "get_attributes: ENTERED", {})
    --reportlog("FILE_MISC_OP", "get_attributes: ENTERED for filename="..filename, {})
    --gets the inode from the DB
    local inode = get_inode_from_filename(filename)
    --logs
    --reportlog("FILE_MISC_OP", "get_attributes: for filename="..filename.." get_inode_from_filename returned=",{inode=inode})
    --if there is no inode returns the error code ENOENT (No such file or directory)
    if not inode then return ENOENT end
    local x = inode.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime
end



reportlog("MAIN_OP", "MAIN: starting SPLAYFUSE",{})

--takes User and Group ID, etc, from FUSE context
local uid,gid,pid,puid,pgid = fuse.context()

reportlog("MAIN_OP", "MAIN: FUSE context taken",{})

--looks if the root_inode is already in the DB
local root_inode = get_inode(1)

reportlog("MAIN_OP", "MAIN: got root_inode",{})

--if there is any, create it
if not root_inode then

    reportlog("FILE_INODE_OP", "MAIN: creating root",{})
    
    root_inode = {
        meta = {
            ino = 1,
            xattr ={greatest_inode_n=1, greatest_block_n=0},
            mode  = mk_mode(7,5,5) + S_IFDIR,
            nlink = 2, uid = puid, gid = pgid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time()
        },
        content = {}
    }

    reportlog("FILE_INODE_OP", "MAIN: gonna put root file",{})
    
    put_file("/", 1)

    reportlog("FILE_INODE_OP", "MAIN: gonna put root inode",{})

    put_inode(1, root_inode)
end

--the splayfuse object, with all the FUSE methods
local splayfuse={

pulse=function()
    --logs entrance
    reportlog("FILE_MISC_OP", "pulse: ENTERED", {})
end,

getattr=function(self, filename)
    --logs entrance
    reportlog("FILE_MISC_OP", "getattr: ENTERED", {})
    --reportlog("FILE_MISC_OP", "getattr: ENTERED for filename="..filename, {})
    --gets the inode from the DB
    local inode = get_inode_from_filename(filename)
    --logs
    --reportlog("FILE_MISC_OP", "get_attributes: for filename="..filename.." get_inode_from_filename returned=",{inode=inode})
    --if there is no inode returns the error code ENOENT (No such file or directory)
    if not inode then return ENOENT end
    local x = inode.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime
end,

opendir=function(self, filename)
    --logs entrance
    --reportlog("DIR_OP", "opendir: ENTERED", {})
    reportlog("DIR_OP", "opendir: ENTERED for filename="..filename, {})
    --gets the inode from the DB
    local inode = get_inode_from_filename(filename)
    --logs
    reportlog("DIR_OP", "opendir: for filename="..filename.." get_inode_from_filename returned",{inode=inode})
    --if there is no inode returns the error code ENOENT (No such file or directory)
    if not inode then return ENOENT end
    --else, returns 0, and the inode object
    return 0, inode
end,

readdir=function(self, filename, offset, inode)
    --logs entrance
    reportlog("DIR_OP", "readdir: ENTERED", {})
    --reportlog("DIR_OP", "readdir: ENTERED for filename="..filename..", offset="..offset, {})
    --looks for the inode; we don't care about the inode on memory (sequential operations condition)
    local inode = get_inode_from_filename(filename)
    --reportlog("DIR_OP", "readdir: inode retrieved", {inode=inode})
    --TODO was commented to check compatibility with memfs
    --[[if not inode then
        return 1
    end
    --]]
    --starts the file list with "." and ".."
    local out={'.','..'}
    --for each entry in content, adds it in the file list
    for k,v in pairs(inode.content) do
        table.insert(out, k)
    end
    return 0, out
end,

releasedir=function(self, filename, inode)
    --logs entrance
    reportlog("DIR_OP", "releasedir: ENTERED", {})
    --reportlog("DIR_OP", "releasedir: ENTERED for filename="..filename, {inode=inode})

    return 0
end,

--function mknod: not sure what it does, it creates a generic node? when is this called
mknod=function(self, filename, mode, rdev)
    --logs entrance
    reportlog("FILE_MISC_OP", "mknod: ENTERED", {})
    --reportlog("FILE_MISC_OP", "mknod: ENTERED for filename="..filename, {mode=mode,rdev=rdev})
    --gets the inode from the DB
    local inode = get_inode_from_filename(filename)
    --if the inode does not exist, we can create it
    if not inode then
        --extracts dir and base from filename
        local dir, base = filename:splitfilename()
        --looks for the parent inode by using the dir
        local parent = get_inode_from_filename(dir)
        
        --declares root_inode
        local root_inode = nil
        --if the parent inode number is 1
        if parent.meta.ino == 1 then
            --the root inode is equal to the parent (like this, there is no need to do another read transaction)
            root_inode = parent
        --if not
        else
            --read the inode from the DB
            root_inode = get_inode(1)
        end

        --increment by 1 the greatest inode number
        root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
        --use a variable to hold the greatest inode number, so we don't have to look in root_inode.meta.xattr all the time
        local greatest_ino = root_inode.meta.xattr.greatest_inode_n
        
        --take User, Group and Process ID from FUSE context
        local uid, gid, pid = fuse.context()
        
        --create the inode
        inode = {
            meta = {
                xattr = {},
                ino = greatest_ino,
                mode = mode,
                dev = rdev, 
                nlink = 1, uid = uid, gid = gid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time()
            },
            content = {""} --TODO: MAYBE THIS IS EMPTY
        }
        
        --logs
        --reportlog("FILE_MISC_OP", "mknod: what is parent_parent?", {parent_parent=parent.parent})
        --add the entry in the parent's inode
        parent.content[base]=true

        --put the parent's inode (changed because it has one more entry)
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        --put the inode itself
        local ok_put_inode = put_inode(greatest_ino, inode)
        --put a file that points to that inode
        local ok_put_file = put_file(filename, greatest_ino)
        --put the root inode, since the greatest inode number changed
        local ok_put_root_inode = put_inode(1, root_inode)
        --returns 0 and the inode
        return 0, inode
    end
end,

read=function(self, filename, size, offset, inode)
    --logs entrance
    reportlog("READ_WRITE_OP", "read: ENTERED", {})
    --reportlog("READ_WRITE_OP", "read: ENTERED for filename="..filename..", size="..size..", offset="..offset, {inode=inode})

    table.insert(to_report_t, "read: started\telapsed_time=0\n")
    local start_time = misc.time()

    local inode = get_inode_from_filename(filename)
    --reportlog("DIR_OP", "readdir: inode retrieved", {inode=inode})
    if not inode then
        return 1
    end

    table.insert(to_report_t, "read: inode retrieved\telapsed_time="..(misc.time()-start_time).."\n")

    local start_block_idx = math.floor(offset / block_size)+1
    local rem_start_offset = offset % block_size
    local end_block_idx = math.floor((offset+size-1) / block_size)+1
    local rem_end_offset = (offset+size-1) % block_size

    --reportlog("READ_WRITE_OP", "read: offset="..offset..", size="..size..", start_block_idx="..start_block_idx, {})
    --reportlog("READ_WRITE_OP", "read: rem_start_offset="..rem_start_offset..", end_block_idx="..end_block_idx..", rem_end_offset="..rem_end_offset, {})

    --reportlog("READ_WRITE_OP", "read: about to get block", {block_n = inode.content[start_block_idx]})

    table.insert(to_report_t, "read: orig_size et al. calculated, size="..size.."\telapsed_time="..(misc.time()-start_time).."\n")

    local block = get_block(inode.content[start_block_idx]) or ""

    local data_t = {}

    table.insert(to_report_t, "read: first block retrieved\telapsed_time="..(misc.time()-start_time).."\n")

    if start_block_idx == end_block_idx then
        --reportlog("READ_WRITE_OP", "read: just one block to read", {})
        table.insert(data_t, string.sub(block, rem_start_offset+1, rem_end_offset))
    else
        --reportlog("READ_WRITE_OP", "read: several blocks to read", {})
        table.insert(data_t, string.sub(block, rem_start_offset+1))

        for i=start_block_idx+1,end_block_idx-1 do
            --reportlog("READ_WRITE_OP", "read: so far data is="..data, {})
        
            table.insert(to_report_t, "read: getting new block\telapsed_time="..(misc.time()-start_time).."\n")
        
            block = get_block(inode.content[i]) or ""
            table.insert(data_t, block)
        end

        table.insert(to_report_t, "read: getting new block\telapsed_time="..(misc.time()-start_time).."\n")

        block = get_block(inode.content[end_block_idx]) or ""
        table.insert(data_t, string.sub(block, 1, rem_end_offset))
    end

    --reportlog("READ_WRITE_OP", "read: finally data is="..data..", size of data="..string.len(data), {})

    --local block = floor(offset/block_size) --JV: NOT NEEDED FOR THE MOMENT
    --local o = offset%block_size --JV: NOT NEEDED FOR THE MOMENT
    --local data={} --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    
    --[[
    if o == 0 and size % block_size == 0 then
        for i=block, block + floor(size/block_size) - 1 do
            data[#data+1]=inode.content[i] or blank_block
        end
    else
        while size > 0 do
            local x = inode.content[block] or blank_block
            local b_size = block_size - o 
            if b_size > size then b_size = size end
            data[#data+1]=x:sub(o+1, b_size)
            o = 0
            size = size - b_size
            block = block + 1
        end
    end --JV: NOT NEEDED FOR THE MOMENT
    --]]

    ----reportlog("READ_WRITE_OP", "read: for filename="..filename.." the full content of inode:", {inode_content=inode.content})

    --if size + offset < string.len(inode.content[1]) then -- JV: CREO QUE ESTO NO SE USA
    --local data = string.sub(inode.content[1], offset, (offset+size)) --JV: WATCH OUT WITH THE LOCAL STUFF... WHEN PUT INSIDE THE IF
    --end --JV: CORRESPONDS TO THE IF ABOVE

    ----reportlog("READ_WRITE_OP", "read: for filename="..filename.." returns", {data=data})

    --return 0, tjoin(data,"") --JV: REMOVED FOR REPLACEMENT WITH DISTDB; data IS ALREADY A STRING
    
    table.insert(to_report_t, "read: finished\telapsed_time="..(misc.time()-start_time).."\n")

    fast_reportlog(table.concat(to_report_t))

    return 0, table.concat(data_t)
end,

write=function(self, filename, buf, offset, inode) --TODO CHANGE DATE WHEN WRITING
    --logs entrance
    reportlog("READ_WRITE_OP", "write: ENTERED", {})
    --reportlog("READ_WRITE_OP", "write: ENTERED for filename="..filename, {buf=buf,offset=offset,inode=inode})
    --logs entrance without reporting buf
    --reportlog("READ_WRITE_OP", "write: ENTERED for filename="..filename, {offset=offset,inode=inode})

    table.insert(to_report_t, "write: started\telapsed_time=0\n")
    local start_time = misc.time()

    local inode = get_inode_from_filename(filename)

    --reportlog("READ_WRITE_OP", "write: inode retrieved", {inode=inode})
    table.insert(to_report_t, "write: inode retrieved\telapsed_time="..(misc.time()-start_time).."\n")
    
    local orig_size = inode.meta.size
    local size = #buf
    
    local start_block_idx = math.floor(offset / block_size)+1
    local rem_start_offset = offset % block_size
    local end_block_idx = math.floor((offset+size-1) / block_size)+1
    local rem_end_offset = ((offset+size-1) % block_size)

    
    --reportlog("READ_WRITE_OP", "write: orig_size="..orig_size..", offset="..offset..", size="..size..", start_block_idx="..start_block_idx, {})
    --reportlog("READ_WRITE_OP", "write: rem_start_offset="..rem_start_offset..", end_block_idx="..end_block_idx..", rem_end_offset="..rem_end_offset, {})

    --reportlog("READ_WRITE_OP", "write: about to get block", {block_n = inode.content[start_block_idx]})

    table.insert(to_report_t, "write: orig_size et al. calculated, size="..size.."\telapsed_time="..(misc.time()-start_time).."\n")

    local block = nil
    local block_n = nil
    local to_write_in_block = nil
    local block_offset = rem_start_offset
    local blocks_created = (end_block_idx > #inode.content)
    local size_changed = ((offset+size) > orig_size)
    local root_inode = nil
    local remaining_buf = buf

    table.insert(to_report_t, "write: calculated more stuff\telapsed_time="..(misc.time()-start_time).."\n")

    if blocks_created then
        root_inode = get_inode(1)
    end

    table.insert(to_report_t, "write: root might have been retrieved\telapsed_time="..(misc.time()-start_time).."\n")

    --reportlog("READ_WRITE_OP", "write: blocks are gonna be created? new file is bigger?", {blocks_created=blocks_created,size_changed=size_changed})

    --reportlog("READ_WRITE_OP", "write: buf="..buf, {})

    for i=start_block_idx, end_block_idx do
        --reportlog("READ_WRITE_OP", "write: im in the for loop, i="..i, {})
        if inode.content[i] then
            --reportlog("READ_WRITE_OP", "write: block exists, so get the block", {})
            block_n = inode.content[i]
            block = get_block(inode.content[i])
        else
            --reportlog("READ_WRITE_OP", "write: block doesnt exists, so create the block", {})
            --reportlog("READ_WRITE_OP", "write: root's xattr=", {root_inode_xattr=root_inode.meta.xattr})
            --reportlog("READ_WRITE_OP", "write: greatest block number=", {root_inode_greatest_block_n=root_inode.meta.xattr.greatest_block_n})
            root_inode.meta.xattr.greatest_block_n = root_inode.meta.xattr.greatest_block_n + 1
            --reportlog("READ_WRITE_OP", "write: greatest block number="..root_inode.meta.xattr.greatest_block_n, {})
            --TODO Concurrent writes can really fuck up the system cause im not writing on root at every time
            block_n = root_inode.meta.xattr.greatest_block_n
            block = ""
            table.insert(inode.content, block_n)
            --reportlog("READ_WRITE_OP", "write: new inode with block", {inode=inode})
        end
        --reportlog("READ_WRITE_OP", "write: remaining_buf="..remaining_buf, {})
        --reportlog("READ_WRITE_OP", "write: (#remaining_buf+block_offset)="..(#remaining_buf+block_offset), {})
        --reportlog("READ_WRITE_OP", "write: block_size="..block_size, {})
        if (#remaining_buf+block_offset) > block_size then
            --reportlog("READ_WRITE_OP", "write: more than block size", {})
            to_write_in_block = string.sub(remaining_buf, 1, (block_size - block_offset))
            remaining_buf = string.sub(remaining_buf, (block_size - block_offset)+1, -1)
        else
            --reportlog("READ_WRITE_OP", "write: less than block size", {})
            to_write_in_block = remaining_buf
        end
        --reportlog("READ_WRITE_OP", "write: block=", {block=block})
        --reportlog("READ_WRITE_OP", "write: to_write_in_block="..to_write_in_block, {})
        --reportlog("READ_WRITE_OP", "write: block_offset="..block_offset..", size of to_write_in_block="..#to_write_in_block, {})
        block = string.sub(block, 1, block_offset)..to_write_in_block..string.sub(block, (block_offset+#to_write_in_block+1)) --TODO CHECK IF THE +1 AT THE END IS OK
        --reportlog("READ_WRITE_OP", "write: now block="..block, {})
        block_offset = 0
        table.insert(to_report_t, "write: before putting the block\telapsed_time="..(misc.time()-start_time).."\n")
        put_block(block_n, block)
        table.insert(to_report_t, "write: timestamp at the end of each cycle\telapsed_time="..(misc.time()-start_time).."\n")
    end

    if size_changed then
        inode.meta.size = offset+size
        put_inode(inode.meta.ino, inode)
        table.insert(to_report_t, "write: inode was written\telapsed_time="..(misc.time()-start_time).."\n")
        if blocks_created then
            put_inode(1, root_inode)
            table.insert(to_report_t, "write: root was written\telapsed_time="..(misc.time()-start_time).."\n")
        end
    end

    table.insert(to_report_t, "\n")

    fast_reportlog(table.concat(to_report_t))

    to_report_t = {}

--[[
    if start_block_idx == end_block_idx then
        if (offset+size) >= orig_size then
            block = string.sub(block, 1, rem_start_offset)..buf
            inode.meta.size = offset+size
            put_inode(inode.meta.ino, inode)
        else
            block = string.sub(block, 1, rem_start_offset)..buf..string.sub(block, rem_end_offset+1) --TODO CHECK IF THE +1 AT THE END IS OK
        end
        put_block(inode.content[start_block_idx], block)
    else
        block = string.sub(block, 1, rem_start_offset)..buf
        local remaining_buf = string.sub(buf, block_size - rem_start_offset, -1)


        if end_block_idx > #inode.content then
            local root_inode = get_inode(1)
            --reportlog("READ_WRITE_OP", "write: new size is bigger", {})
            local orig_n_blocks = #inode.content
            for i=start_block_idx+1, orig_n_blocks do
                --reportlog("READ_WRITE_OP", "write: remaining_buf="..remaining_buf, {})
                block = string.sub(remaining_buf, 1, block_size)
                put_block(inode.content[i], block)
                remaining_buf = string.sub(remaining_buf, block_size+1, -1) --TODO CHECK ABOUT +1
            end

            local block_n = nil

            for i=orig_n_blocks+1, end_block_idx-1 do
                --reportlog("READ_WRITE_OP", "write: remaining_buf="..remaining_buf, {})
                block = string.sub(remaining_buf, 1, block_size)
                root_inode.meta.xattr.greatest_block_n = root_inode.meta.xattr.greatest_block_n + 1
                --TODO Concurrent writes can really fuck up the system cause im not writing on root at every time
                block_n = root_inode.meta.xattr.greatest_block_n
                put_block(block_n, block)
                table.insert(inode.content, block_n)
                remaining_buf = string.sub(remaining_buf, block_size+1, -1) --TODO CHECK ABOUT +1
            end

            root_inode.meta.xattr.greatest_block_n = root_inode.meta.xattr.greatest_block_n + 1
            block_n = root_inode.meta.xattr.greatest_block_n
            block = remainig_buf
            put_block(block_n, block) --TODO CONSISTENT OK = PUT OR JUST PUT
            put_inode(inode.meta.ino, inode)
            put_inode(1, root_inode)
            
        else
            for i=start_block_idx+1,end_block_idx-1 do
                --reportlog("READ_WRITE_OP", "write: remaining_buf="..remaining_buf, {})
                block = string.sub(remaining_buf, 1, block_size)
                put_block(inode.content[i], block)
                remaining_buf = string.sub(remaining_buf, block_size+1, -1) --TODO CHECK ABOUT +1
            end

            if (offset+size) >= orig_size then
                block = remainig_buf
            else
                block = get_block(inode.content[end_block_idx])
                block = remaining_buf..string.sub(block, rem_end_offset+1) --TODO CHECK IF THE +1 AT THE END IS OK
            end
            put_block(inode.content[end_block_idx], block) --TODO CONSISTENT OK = PUT OR JUST PUT
        end
        

    end
    --]]

    --[[
    local o = offset % block_size
    local block = floor(offset / block_size)
    if o == 0 and size % block_size == 0 then
        local start = 0
        for i=block, block + floor(size/block_size) - 1 do
            inode.content[i] = buf:sub(start + 1, start + block_size)
            start = start + block_size
        end
    else
        local start = 0
        while size > 0 do
            local x = inode.content[block] or blank_block
            local b_size = block_size - o 
            if b_size > size then b_size = size end
            inode.content[block] = tjoin({x:sub(1, o), buf:sub(start+1, start + b_size), x:sub(o + 1 + b_size)},"")
            o = 0
            size = size - b_size
            block = block + 1
        end
    end --JV: NOT NEEDED FOR THE MOMENT
    
    --reportlog("READ_WRITE_OP", "write: CHECKPOINT1",{})
    if not inode.content[1] then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        inode.content[1] = "" --JV: ADDED FOR REPLACEMENT WITH DISTDB
        --reportlog("READ_WRITE_OP", "write: CHECKPOINT1a",{})
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    --reportlog("READ_WRITE_OP", "write: CHECKPOINT2",{})
    local old_content = inode.content[1] --JV: ADDED FOR REPLACEMENT WITH DISTDB
    local old_size = string.len(inode.content[1])
    if (offset+size) < old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        inode.content[1] = string.sub(old_content, 1, offset)..buf..string.sub(old_content, (offset+size+1), -1) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        --reportlog("READ_WRITE_OP", "write: CHECKPOINT3a",{})
    else --JV: ADDED FOR REPLACEMENT WITH DISTDB
        --reportlog("READ_WRITE_OP", "write: CHECKPOINT3b",{})
        inode.content[1] = string.sub(old_content, 1, offset)..buf --JV: ADDED FOR REPLACEMENT WITH DISTDB
        if (offset+size) > old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
            --reportlog("READ_WRITE_OP", "write: CHECKPOINT3c",{})
            inode.meta.size = offset+size --JV: ADDED FOR REPLACEMENT WITH DISTDB
            --inode.meta_changed = true --JV: ADDED FOR REPLACEMENT WITH DISTDB
        end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB

    --local eof = offset + #buf --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    --if eof > inode.meta.size then inode.meta.size = eof ; inode.meta_changed = true end --JV: REMOVED FOR REPLACEMENT WITH DISTDB

    local ok_put_inode = put_inode(inode.meta.ino, inode) --JV: ADDED FOR REPLACEMENT WITH DISTDB
    --]]
    return #buf
end,

open=function(self, filename, mode) --NOTE: MAYBE OPEN DOESN'T DO ANYTHING BECAUSE OF THE SHARED NATURE OF THE FILESYSTEM; EVERY WRITE READ MUST BE ATOMIC AND
--LONG SESSIONS WITH THE LIKES OF OPEN HAVE NO SENSE.
--TODO: CHECK ABOUT MODE AND USER RIGHTS.
    --logs entrance
    reportlog("FILE_MISC_OP", "open: ENTERED", {})
    --reportlog("FILE_MISC_OP", "open: ENTERED for filename="..filename, {mode=mode})

    local m = mode % 4
    local inode = get_inode_from_filename(filename)
    --[[
    --TODO: CHECK THIS MODE THING
    if not inode then return ENOENT end
    inode.open = (inode.open or 0) + 1
    put_inode(inode.meta.ino, inode)
    --TODO: CONSIDER CHANGING A FIELD OF THE DISTDB WITHOUT RETRIEVING THE WHOLE OBJECT; DIFFERENTIAL WRITE
    --]]
    return 0, inode
end,

release=function(self, filename, inode) --NOTE: RELEASE DOESNT SEEM TO MAKE MUCH SENSE
    --logs entrance
    reportlog("FILE_MISC_OP", "release: ENTERED", {})
    --reportlog("FILE_MISC_OP", "release: ENTERED for filename="..filename, {inode=inode})

    --[[
    inode.open = inode.open - 1
    --reportlog("_OP", "release: for filename="..filename, {inode_open=inode.open})
    if inode.open < 1 then
        --reportlog("_OP", "release: open < 1", {})
        if inode.changed then
            --reportlog("_OP", "release: gonna put", {})
            local ok_put_inode = put_inode(inode.ino, inode)
        end
        if inode.meta_changed then
            --reportlog("_OP", "release: gonna put", {})
            local ok_put_inode = put_inode(inode.ino, inode)
        end
        --reportlog("_OP", "release: meta_changed = nil", {})
        inode.meta_changed = nil
        --reportlog("_OP", "release: changed = nil", {})
        inode.changed = nil
    end
    --]]
    return 0
end,

fgetattr=function(self, filename, inode, ...) --TODO: CHECK IF fgetattr IS USEFUL, IT IS! TODO: CHECK WITH filename
    --logs entrance
    reportlog("FILE_MISC_OP", "fgetattr: ENTERED", {})
    --reportlog("FILE_MISC_OP", "fgetattr: ENTERED for filename="..filename, {inode=inode})
    return get_attributes(filename)
end,

rmdir=function(self, filename)
    --logs entrance
    reportlog("DIR_OP", "rmdir: ENTERED", {})
    --reportlog("DIR_OP", "rmdir: ENTERED for filename="..filename, {})

    local inode_n = get_inode_n(filename)

    if inode_n then --TODO: WATCH OUT, I PUT THIS IF
        local dir, base = filename:splitfilename()

        --local inode = get_inode_from_filename(filename)
        --TODO: CHECK WHAT HAPPENS WHEN TRYING TO ERASE A NON-EMPTY DIR
        ----reportlog("_OP", "rmdir: got inode", {inode, inode})

        local parent = get_inode_from_filename(dir)
        parent.content[base] = nil
        parent.meta.nlink = parent.meta.nlink - 1

        delete_file(filename)
        delete_dir_inode(inode_n)
        put_inode(parent.ino, parent)
    end
    return 0
end,

mkdir=function(self, filename, mode, ...) --TODO: CHECK WHAT HAPPENS WHEN TRYING TO MKDIR A DIR THAT EXISTS
--TODO: MERGE THESE CODES (MKDIR, MKNODE, CREATE) ON 1 FUNCTION
    --logs entrance
    reportlog("DIR_OP", "mkdir: ENTERED", {})
    --reportlog("DIR_OP", "mkdir: ENTERED for filename="..filename, {mode=mode})

    local inode = get_inode_from_filename(filename)

    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        --declares root_inode
        local root_inode = nil
        --if the parent inode number is 1
        if parent.meta.ino == 1 then
            --the root inode is equal to the parent (like this, there is no need to do another read transaction)
            root_inode = parent
        --if not
        else
            --read the inode from the DB
            root_inode = get_inode(1)
        end

        root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
        local greatest_ino = root_inode.meta.xattr.greatest_inode_n
        
        local uid, gid, pid = fuse.context()
        
        inode = {
            meta = {
                xattr = {},
                mode = set_bits(mode,S_IFDIR),
                ino = greatest_ino, 
                dev = 0, --TODO: CHECK IF USEFUL
                nlink = 2, uid = uid, gid = gid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time() --TODO: CHECK IF SIZE IS NOT block_size
            },
            content = {}
        }
        
        parent.content[base]=true
        parent.meta.nlink = parent.meta.nlink + 1

        --put the parent's inode, because the contents changed
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        --put the inode, because it's new
        local ok_put_inode = put_inode(greatest_ino, inode)
        --put the file, because it's new
        local ok_put_file = put_file(filename, greatest_ino)
        --put root inode, because greatest ino was incremented
        local ok_put_root_inode = put_inode(1, root_inode)
    end
    return 0
end,

create=function(self, filename, mode, flag, ...)
    --logs entrance
    reportlog("FILE_MISC_OP", "create: ENTERED for filename",{})
    --reportlog("FILE_MISC_OP", "create: ENTERED for filename="..filename,{mode=mode,flag=flag})

    local inode = get_inode_from_filename(filename)

    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = nil
        if parent.meta.ino == 1 then
            root_inode = parent
        else
            root_inode = get_inode(1)
        end

        root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
        local greatest_ino = root_inode.meta.xattr.greatest_inode_n
        
        local uid, gid, pid = fuse.context()
        
        inode = {
            meta = {
                xattr = {},
                mode  = set_bits(mode, S_IFREG),
                ino = greatest_ino, 
                dev = 0, 
                nlink = 1, uid = uid, gid = gid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time()
            },
            content = {}
        }
        
        parent.content[base]=true

        --put the parent's inode, because the contents changed
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        --put the inode, because it's new
        local ok_put_inode = put_inode(greatest_ino, inode)
        --put the file, because it's new
        local ok_put_file = put_file(filename, greatest_ino)
        --put root inode, because greatest ino was incremented
        local ok_put_root_inode = put_inode(1, root_inode)
        return 0, inode
    end
end,

flush=function(self, filename, inode)
    --logs entrance
    reportlog("FILE_MISC_OP", "flush: ENTERED", {})
    --reportlog("FILE_MISC_OP", "flush: ENTERED for filename="..filename, {inode=inode})

    if inode.changed then
        --TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
    end
    return 0
end,

readlink=function(self, filename)
    --logs entrance
    reportlog("LINK_OP", "readlink: ENTERED", {})
    --reportlog("LINK_OP", "readlink: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    if inode then
        return 0, inode.content[1]
    end
    return ENOENT
end,

symlink=function(self, from, to)
    --logs entrance
    reportlog("LINK_OP", "symlink: ENTERED",{})
    --reportlog("LINK_OP", "symlink: ENTERED",{from=from,to=to})

    local to_dir, to_base = to:splitfilename()
    local to_parent = get_inode_from_filename(to_dir)

    local root_inode = nil
    if to_parent.meta.ino == 1 then
        root_inode = to_parent
    else
        root_inode = get_inode(1)
    end

    --reportlog("LINK_OP", "symlink: root_inode retrieved",{root_inode=root_inode})

    root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
    local greatest_ino = root_inode.meta.xattr.greatest_inode_n

    local uid, gid, pid = fuse.context()

    local to_inode = {
        meta = {
            xattr = {},
            mode= S_IFLNK+mk_mode(7,7,7),
            ino = greatest_ino, 
            dev = 0, 
            nlink = 1, uid = uid, gid = gid, size = string.len(from), atime = os.time(), mtime = os.time(), ctime = os.time()
        },
        content = {from}
    }

    to_parent.content[to_base]=true

    --put the to_parent's inode, because the contents changed
    local ok_put_to_parent_inode = put_inode(to_parent.meta.ino, to_parent)
    --put the to_inode, because it's new
    local ok_put_inode = put_inode(greatest_ino, to_inode)
    --put the file, because it's new
    local ok_put_file = put_file(to, greatest_ino)
    --put root inode, because greatest ino was incremented
    local ok_put_root_inode = put_inode(1, root_inode)
    return 0 --TODO this return 0 was inside an IF
end,

rename=function(self, from, to)
    --logs entrance
    reportlog("MV_CP_OP", "rename: ENTERED", {})
    --reportlog("MV_CP_OP", "rename: ENTERED, from="..from..", to="..to, {})

    if from == to then return 0 end

    local from_inode = get_inode_from_filename(from)
    
    if from_inode then

        --reportlog("MV_CP_OP", "rename: entered in IF", {from_inode=from_inode})
        
        local from_dir, from_base = from:splitfilename()
        local to_dir, to_base = to:splitfilename()
        local from_parent = get_inode_from_filename(from_dir)
        local to_parent = nil
        if to_dir == from_dir then
            to_parent = from_parent
        else
            to_parent = get_inode_from_filename(to_dir)
        end

        to_parent.content[to_base] = true
        from_parent.content[from_base] = nil
        
        --reportlog("MV_CP_OP", "rename: changes made", {to_parent=to_parent, from_parent=from_parent})
        --TODO: CHECK IF IT IS A DIR

        --only if to and from are different (avoids writing on parent's inode twice, for the sake of efficiency)
        if to_dir ~= from_dir then
            --put the to_parent's inode, because the contents changed
            local ok_put_to_parent_inode = put_inode(to_parent.meta.ino, to_parent)
        end
        --put the from_parent's inode, because the contents changed
        local ok_put_from_parent_inode = put_inode(from_parent.meta.ino, from_parent)
        --put the to_file, because it's new
        local ok_put_file = put_file(to, from_inode.meta.ino)
        --delete the from_file
        local ok_delete_file = delete_file(from)
        
        --[[
        if (inode.open or 0) < 1 then
            --mnode.flush_node(inode,to, true) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
            local ok_write_in_db_inode = write_in_db(to, inode) --JV: ADDED FOR REPLACEMENT WITH DISTDB
            --TODO: WTF DO I DO HERE?
        else
            inode.meta_changed = true
        end
        --]]
        return 0
    end
end,

link=function(self, from, to, ...)
    --logs entrance
    reportlog("LINK_OP", "link: ENTERED", {})
    --reportlog("LINK_OP", "link: ENTERED, from="..from..", to="..to, {})
   
    if from == to then return 0 end

    local from_inode = get_inode_from_filename(from)
    
    --reportlog("LINK_OP", "link: from_inode", {from_inode=from_inode})

    if from_inode then
        --reportlog("LINK_OP", "link: entered in IF", {})
        local to_dir, to_base = to:splitfilename()
        --reportlog("LINK_OP", "link: to_dir="..to_dir..", to_base="..to_base, {})
        local to_parent = get_inode_from_filename(to_dir)
        --reportlog("LINK_OP", "link: to_parent", {to_parent=to_parent})
        
        to_parent.content[to_base] = true
        --reportlog("LINK_OP", "link: added file in to_parent", {to_parent=to_parent})
        from_inode.meta.nlink = from_inode.meta.nlink + 1
        --reportlog("LINK_OP", "link: incremented nlink in from_inode", {from_inode=from_inode})

        --put the to_parent's inode, because the contents changed
        local ok_put_to_parent = put_inode(to_parent.meta.ino, to_parent)
        --put the inode, because nlink was incremented
        local ok_put_inode = put_inode(from_inode.meta.ino, from_inode)
        --put the to_file, because it's new
        local ok_put_file = put_file(to, from_inode.meta.ino)
        return 0
    end
end,

unlink=function(self, filename, ...)
    --logs entrance
    reportlog("LINK_OP", "unlink: ENTERED", {})
    --reportlog("LINK_OP", "unlink: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    
    if inode then
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)

        --reportlog("LINK_OP", "unlink: parent retrieved:", {parent=parent})
        
        parent.content[base] = nil

        --reportlog("LINK_OP", "unlink: link to file in parent removed", {parent=parent})

        inode.meta.nlink = inode.meta.nlink - 1

        --reportlog("LINK_OP", "unlink: now inode has less links", {inode=inode})
        
        --delete the file, because it's being unlinked
        local ok_delete_file = delete_file(filename)
        --put the parent ino, because the record of the file was deleted
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        --if the inode has no more links
        if inode.meta.nlink == 0 then
            --reportlog("LINK_OP", "unlink: i have to delete the inode too", {})
            --delete the inode, since it's not linked anymore
            delete_inode(inode.meta.ino)
        else
            local ok_put_inode = put_inode(inode.meta.ino, inode)
        end
        return 0
    else
        --reportlog("_OP", "unlink: ERROR no inode", {})
        return ENOENT
    end
end,

chown=function(self, filename, uid, gid)
    --logs entrance
    reportlog("FILE_MISC_OP", "chown: ENTERED", {})
    --reportlog("FILE_MISC_OP", "chown: ENTERED for filename="..filename..", uid="..uid..", gid="..gid, {})

    local inode = get_inode_from_filename(filename)
    if inode then
        inode.meta.uid = uid
        inode.meta.gid = gid
        local ok_put_inode = put_inode(inode.meta.ino, inode)
        return 0
    else
        return ENOENT
    end
end,

chmod=function(self, filename, mode)
    --logs entrance
    reportlog("FILE_MISC_OP", "chmod: ENTERED", {})
    --reportlog("FILE_MISC_OP", "chmod: ENTERED for filename="..filename, {mode=mode})

    local inode = get_inode_from_filename(filename)
    if inode then
        inode.meta.mode = mode
        local ok_put_inode = put_inode(inode.meta.ino, inode)
        return 0
    else
        return ENOENT
    end
end,

utime=function(self, filename, atime, mtime)
    --logs entrance
    reportlog("FILE_MISC_OP", "utime: ENTERED", {})
    --reportlog("FILE_MISC_OP", "utime: ENTERED for filename="..filename, {atime=atime,mtime=mtime})

    local inode = get_inode_from_filename(filename)
    
    if inode then
        inode.meta.atime = atime
        inode.meta.mtime = mtime
        local ok_put_inode = put_inode(inode.meta.ino, inode)
        return 0
    else
        return ENOENT
    end
end,
ftruncate=function(self, filename, size, inode)
    --logs entrance
    reportlog("FILE_MISC_OP", "ftruncate: ENTERED", {})
    --reportlog("FILE_MISC_OP", "ftruncate: ENTERED for filename="..filename, {size=size,inode=inode})
    
    local orig_size = inode.meta.size

    local block_idx = math.floor((size - 1) / block_size) + 1
    local rem_offset = size % block_size

    --reportlog("FILE_MISC_OP", "ftruncate: orig_size="..orig_size..", new_size="..size..", block_idx="..block_idx..", rem_offset="..rem_offset, {})
        
    for i=#inode.content, block_idx+1,-1 do
        --reportlog("FILE_MISC_OP", "ftruncate: about to remove block number inode.content["..i.."]="..inode.content[i], {})
        local ok_delete_from_db_block = delete_block(inode.content[i])
        table.remove(inode.content, i)
    end

    --reportlog("FILE_MISC_OP", "ftruncate: about to change block number inode.content["..block_idx.."]="..inode.content[block_idx], {})

    

    if rem_offset == 0 then
        --reportlog("FILE_MISC_OP", "truncate: last block must be empty, so we delete it", {})
        local ok_delete_from_db_block = delete_block(inode.content[block_idx])
        table.remove(inode.content, block_idx)
    else
        --reportlog("FILE_MISC_OP", "truncate: last block is not empty", {})
        local last_block = get_block(block_idx)
        --reportlog("FILE_MISC_OP", "truncate: it already has this="..last_block, {})
        local write_in_last_block = string.sub(last_block, 1, rem_offset)
        --reportlog("FILE_MISC_OP", "truncate: and we change to this="..write_in_last_block, {})
        local ok_put_block = put_block(inode.content[block_idx], write_in_last_block)
    end

    inode.meta.size = size

    --reportlog("FILE_MISC_OP", "truncate: about to write inode", {})

    local ok_put_inode = put_inode(inode.meta.ino, inode)

    return 0
end,

truncate=function(self, filename, size)
    --logs entrance
    reportlog("FILE_MISC_OP", "truncate: ENTERED", {})
    --reportlog("FILE_MISC_OP", "truncate: ENTERED for filename="..filename, {size=size})
    
    local inode = get_inode_from_filename(filename)
    
    --reportlog("FILE_MISC_OP", "truncate: inode was retrieved", {inode=inode})

    if inode then

        local orig_size = inode.meta.size

        local block_idx = math.floor((size - 1) / block_size) + 1
        local rem_offset = size % block_size

        --reportlog("FILE_MISC_OP", "truncate: orig_size="..orig_size..", new_size="..size..", block_idx="..block_idx..", rem_offset="..rem_offset, {})
        
        for i=#inode.content, block_idx+1,-1 do
            --reportlog("FILE_MISC_OP", "truncate: about to remove block number inode.content["..i.."]="..inode.content[i], {})
            local ok_delete_from_db_block = delete_block(inode.content[i])
            table.remove(inode.content, i)
        end

        if block_idx > 0 then
            --reportlog("FILE_MISC_OP", "truncate: about to change block number inode.content["..block_idx.."]="..inode.content[block_idx], {})

            if rem_offset == 0 then
                --reportlog("FILE_MISC_OP", "truncate: last block must be empty, so we delete it", {})
            
                local ok_delete_from_db_block = delete_block(inode.content[block_idx])
                table.remove(inode.content, block_idx)
            else
                --reportlog("FILE_MISC_OP", "truncate: last block is not empty", {})
                local last_block = get_block(block_idx)
                --reportlog("FILE_MISC_OP", "truncate: it already has this="..last_block, {})
                local write_in_last_block = string.sub(last_block, 1, rem_offset)
                --reportlog("FILE_MISC_OP", "truncate: and we change to this="..write_in_last_block, {})
                local ok_put_block = put_block(inode.content[block_idx], write_in_last_block)
            end
        end

        inode.meta.size = size

        --reportlog("FILE_MISC_OP", "truncate: about to write inode", {})

        local ok_put_inode = put_inode(inode.meta.ino, inode)

        return 0
    else
        return ENOENT
    end
end,

access=function(...)
    --logs entrance
    reportlog("FILE_MISC_OP", "access: ENTERED",{})
    
    return 0
end,

fsync=function(self, filename, isdatasync, inode)
    --logs entrance
    reportlog("FILE_MISC_OP", "fsync: ENTERED", {})
    --reportlog("FILE_MISC_OP", "fsync: ENTERED for filename="..filename, {isdatasync=isdatasync,inode=inode})
    --TODO: PA DESPUES
    --[[
    mnode.flush_node(inode, filename, false) 
    if isdatasync and inode.changed then 
        mnode.flush_data(inode.content, inode, filename) 
    end
    --]]
    return 0
end,
fsyncdir=function(self, filename, isdatasync, inode)
    --logs entrance
    reportlog("FILE_MISC_OP", "fsyncdir: ENTERED", {})
    --reportlog("FILE_MISC_OP", "fsyncdir: ENTERED for filename="..filename, {isdatasync=isdatasync,inode=inode})

    return 0
end,
listxattr=function(self, filename, size)
    --logs entrance
    reportlog("FILE_MISC_OP", "listxattr: ENTERED", {})
    --reportlog("FILE_MISC_OP", "listxattr: ENTERED for filename="..filename, {size=size})

    local inode = get_inode_from_filename(filename)
    if inode then
        local v={}
        for k in pairs(inode.meta.xattr) do 
            if type(k) == "string" then v[#v+1]=k end
        end
        return 0, table.concat(v,"\0") .. "\0"
    else
        return ENOENT
    end
end,

removexattr=function(self, filename, name)
    --logs entrance
    reportlog("FILE_MISC_OP", "removexattr: ENTERED", {})
    --reportlog("FILE_MISC_OP", "removexattr: ENTERED for filename="..filename, {name=name})

    local inode = get_inode_from_filename(filename)
    if inode then
        inode.meta.xattr[name] = nil
        local ok_put_inode = put_inode(inode.meta.ino, inode)
        return 0
    else
        return ENOENT
    end
end,

setxattr=function(self, filename, name, val, flags)
    --logs entrance
    reportlog("FILE_MISC_OP", "setxattr: ENTERED", {})
    --reportlog("FILE_MISC_OP", "setxattr: ENTERED for filename="..filename, {name=name,val=val,flags=flags})

    --string.hex=function(s) return s:gsub(".", function(c) return format("%02x", string.byte(c)) end) end
    local inode = get_inode_from_filename(filename)
    if inode then
        inode.meta.xattr[name]=val
        local ok_put_inode = put_inode(inode.meta.ino, inode)
        return 0
    else
        return ENOENT
    end
end,

getxattr=function(self, filename, name, size)
    --logs entrance
    reportlog("FILE_MISC_OP", "getxattr: ENTERED", {})
    --reportlog("FILE_MISC_OP", "getxattr: ENTERED for filename="..filename, {name=name,size=size})

    local inode = get_inode_from_filename(filename)
    --reportlog("FILE_MISC_OP", "getxattr: get_inode was successful", {inode=inode})
    if inode then
        --reportlog("FILE_MISC_OP", "getxattr: retrieving xattr["..name.."]=", {inode_meta_xattr=inode.meta.xattr[name]})
        return 0, inode.meta.xattr[name] or "" --not found is empty string
    else
        return ENOENT
    end
end,

statfs=function(self,filename)
    local inode,parent = get_inode_from_filename(filename)
    local o = {bs=block_size,blocks=64,bfree=48,bavail=48,bfiles=16,bffree=16}
    return 0, o.bs, o.blocks, o.bfree, o.bavail, o.bfiles, o.bffree
end
}

--profiler.start()

reportlog("MAIN_OP", "MAIN: before defining fuse_opt", {})

fuse_opt = { 'splayfuse', 'mnt', '-f', '-s', '-d', '-oallow_other'}

reportlog("MAIN_OP", "MAIN: fuse_opt defined", {})

if select('#', ...) < 2 then
    print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
    os.exit(1)
end

reportlog("MAIN_OP", "MAIN: gonna execute fuse.main", {})

fuse.main(splayfuse, {...})

--profiler.stop()