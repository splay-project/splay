#!/usr/bin/env lua
--[[
	SplayFUSE: Distributed FS in FUSE using the LUA bindings
	Copyright 2011-2013 José Valerio (University of Neuchâtel)

	Based on:
	
	Memory FS in FUSE using the lua binding
	Copyright 2007 (C) gary ng <linux@garyng.com>

	This program can be distributed under the terms of the GNU LGPL.
]]


--REQUIRED LIBRARIES

--fuse is for the Lua bindings
local fuse = require"fuse"
--distdb-client contains APIs send-get, -put, -delete to communicate with the distDB
local dbclient = require"distdb-client"
--lbinenc is used for serialization
local serializer = require"splay.lbinenc"
--crypto is used for hashing
local crypto = require"crypto"
--splay.misc used for misc.time
local misc = require"splay.misc"
--logger provides some fine tunable logging functions
local logger = require"logger"
--profiler is used for Lua profiling
--require'profiler'

--"CONSTANTS"

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


--LOCAL VARIABLES

local block_size = 48
local blank_block=string.rep("0", block_size)
local open_mode={'rb','wb','rb+'}

--consistency types can be "evtl_consistent", "paxos" or "consistent"
local inode_ctype = "consistent"
local block_ctype = "consistent"
--the URL of the Entry Point to the distDB
local db_url = "127.0.0.1:15272"


--LOCAL VARIABLES FOR LOGGING

log_domains.MAIN_OP = true
log_domains.FILE_INODE_OP = true
log_domains.DIR_OP = true
log_domains.LINK_OP = true
log_domains.READ_WRITE_OP = true
log_domains.FILE_MISC_OP = true
log_domains.MV_CP_OP = true


--MISC FUNCTIONS

--function splitfilename: splits the filename into parent dir and basename; for example: "/usr/include/lua/5.1/lua.h" -> "/usr/include/lua/5.1", "lua.h"
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

--bit logic used for the mode field. TODO: replace the mode field in file's metadata with a table (if I have the time, it's not really necessary)
--tab[i+1][j+1] = xor(i, j) where i,j in (0-15)
local tab = {
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

	--last_logprint("FILE_INODE_OP", "decode_acl: START. s=", s)

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "mk_mode"
	local log_domain, function_name = "FILE_INODE_OP", "mk_mode"
	--logs entrance
	--logprint(log_domain, function_name..": START. owner=", owner, ", group=", group, ", world=", world)
	--logprint(log_domain, tbl2str("sticky", 0 ,sticky))
	--if sticky is not specified, fills it out with 0
	sticky = sticky or 0
	--result mode is the combination of the owner, group, world rights and the sticky mode
	local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID
	--flushes all logs
	--last_logprint(log_domain, function_name..": END. returns result_mode=", result_mode)
	--returns the mode
	return result_mode
end

local function hash_string(str)
	return crypto.evp.digest("sha1", str)
end


--FS TO DB FUNCTIONS

--function get_block: gets a block from the DB
function get_block(block_id)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "get_block"
	local log_domain, function_name = "FILE_INODE_OP", "get_block"
	--logs entrance
	--logprint(log_domain, function_name..": START. block_id=\""..block_id.."\"")
	--reads the file element from the DB
	local ok, data = send_get(db_url, block_id, block_ctype)
	--if the reading was not successful
	if not ok then
		--reports the error, flushes all logs and return nil
		--last_logprint(log_domain, function_name..": ERROR, read_from_db of block was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END.")
	--if everything went well, it returns the inode number
	return data
end

--function get_inode: gets a inode element from the DB
function get_inode(inode_n)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "get_inode"
	local log_domain, function_name = "FILE_INODE_OP", "get_inode"
	--safety if: if the inode_n is not a number
	if type(inode_n) ~= "number" then
		--flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": inode_n not a number, returning nil")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. inode_n=", inode_n)
	--reads the inode element from the DB
	local ok, inode_serialized = send_get(db_url, hash_string("inode:"..inode_n), inode_ctype)
	--logs
	--logprint(log_domain, function_name..": read_from_db returned=")
	--logprint(log_domain, tbl2str("ok_read_from_db_inode", 0, ok_read_from_db_inode))
	--logprint(log_domain, tbl2str("inode_serialized", 0, inode_serialized))
	--if the reading was not successful
	if not ok then
		--reports the error and returns nil
		--last_logprint(log_domain, function_name..": ERROR, read_from_db of inode was not OK")
		return nil
	end
	--if the requested record is empty
	if not inode_serialized then
		--reports the error and returns nil
		--last_logprint(log_domain, function_name..": inode_serialized is nil, returning nil")
		return nil
	end
	--logs
	--logprint(log_domain, function_name..": trying to serializer_decode, type of inode_serialized=", type(inode_serialized))
	--deserializes the inode
	local inode = serializer.decode(inode_serialized)
	--logs
	--logprint(log_domain, function_name..": read_from_db returned")
	--flushes all logs
	--last_logprint(log_domain, tbl2str("inode", 0, inode))
	--returns the inode
	return inode
end

--function get_inode_n: gets a inode number from the DB, by identifying it with the filename
function get_inode_n(filename)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "get_inode_n"
	local log_domain, function_name = "FILE_INODE_OP", "get_inode_n"
	--checks input errors
	--safety if: if the filename is not a string or an empty string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": filename not a valid string, returning nil")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. filename=", filename)
	--reads the file element from the DB
	local ok, inode_n = send_get(db_url, hash_string("file:"..filename), inode_ctype)
	--if the reading was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, read_from_db of file was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": inode_n=", inode_n)
	--returns the inode number
	return tonumber(inode_n)
end

--function get_inode_from_filename: gets a inode element from the DB, by identifying it with the filename
function get_inode_from_filename(filename)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "get_inode_from_filename"
	local log_domain, function_name = "FILE_INODE_OP", "get_inode_from_filename"
	--checks input errors
	--safety if: if the filename is not a string or an empty string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": filename not a valid string, returning nil")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. filename=", filename)
	--the inode number is extracted by calling get_inode_n
	local inode_n = get_inode_n(filename)
	--flushes all logs
	--last_logprint(log_domain, function_name..": inode number retrieved inode_n=", inode_n)
	--returns the corresponding inode
	return get_inode(inode_n)
end

--function put_block: puts a block element into the DB
function put_block(block_id, data)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_INODE_OP", "put_block"
	--checks input errors
	--if data is not a string
	if type(data) ~= "string" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": data not a string, returning nil")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. block_id=", block_id, "data size=", string.len(data))
	--writes the block in the DB
	local ok = send_put(db_url, block_id, block_ctype, data)
	--if the writing was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, write_in_db of block was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns the blockID
	return true
end

--function put_inode: puts a inode element into the DB
function put_inode(inode_n, inode)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_inode"
	local log_domain, function_name = "FILE_INODE_OP", "put_inode"
	--checks input errors
	--if inode_n is not a number
	if type(inode_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--if inode is not a table
	if type(inode) ~= "table" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, inode not a table")
		return nil
	end	

	--logs entrance
	--logprint(log_domain, function_name..": START. inode_n=", inode_n)
	--logprint(log_domain, tbl2str("inode", 0, inode))

	--writes the inode in the DB
	local ok = send_put(db_url, hash_string("inode:"..inode_n), inode_ctype, serializer.encode(inode))
	--if the writing was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, write_in_db of inode was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function put_file: puts a file element into the DB
function put_file(filename, inode_n)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_file"
	local log_domain, function_name = "FILE_INODE_OP", "put_file"
	--checks input errors
	--if filename is not a string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, filename not a string")
		return nil
	end
	--if inode_n is not a number
	if type(inode_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. filename=", filename, "inode_n=", inode_n)

	--writes the file in the DB
	local ok = send_put(db_url, hash_string("file:"..filename), inode_ctype, inode_n)
	--if the writing was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, write_in_db of file was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function delete_block: deletes a block element from the DB
function delete_block(block_id)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "delete_block"
	local log_domain, function_name = "FILE_INODE_OP", "delete_block"
	--logs entrance
	--logprint(log_domain, function_name..": START. block_n=", block_n)
	--deletes the block from the DB
	local ok = send_delete(db_url, block_id, block_ctype)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function delete_inode: deletes an inode element from the DB
function delete_inode(inode_n)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "delete_inode"
	local log_domain, function_name = "FILE_INODE_OP", "delete_inode"
	--TODO: WEIRD LATENCY IN DELETE_LOCAL, I THINK THE INODE DOES NOT GET DELETED.
	--checks input errors
	--if inode_n is not a number
	if type(inode_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. inode_n=", inode_n)
	--reads the inode element from the DB
	local inode = get_inode(inode_n)
 	--for all the blocks refered by the inode
	for i,v in ipairs(inode.content) do
		--deletes the blocks. TODO: NOT CHECKING IF SUCCESSFUL
		delete_block(v)
	end
	--deletes the inode from the DB
	local ok = send_delete(db_url, hash_string("inode:"..inode_n), inode_ctype)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function delete_dir_inode: deletes a directory inode element from the DB
function delete_dir_inode(inode_n)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "delete_dir_inode"
	local log_domain, function_name = "FILE_INODE_OP", "delete_dir_inode"
	--checks input errors
	--if inode_n is not a number
	if type(inode_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. inode_n=", inode_n)
	--deletes the inode from the DB
	local ok = send_delete(db_url, hash_string("inode:"..inode_n), inode_ctype)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function delete_file: deletes a file element from the DB
function delete_file(filename)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "delete_file"
	local log_domain, function_name = "FILE_INODE_OP", "delete_file"
	--if filename is not a string or it is an empty string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns nil
		--logprint(log_domain, function_name..": ERROR, filename not a string")
		return nil
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. filename=", filename)
	--deletes the file element from the DB
	local ok = send_delete(db_url, hash_string("file:"..filename), inode_ctype)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function get_attributes: gets the attributes of a file
--BIG TODOS: cambiar block a id=hash(content) e inode a id=hash(random). pierre dice que el Entry Point debe ser stateful.
function get_attributes(filename)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "get_attributes"
	local log_domain, function_name = "FILE_INODE_OP", "get_attributes"
	--if filename is not a string or it is an empty string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
		--logprint(log_domain, function_name..": END. filename not a valid string, returning ENOENT")
		return ENOENT
	end
	--logs entrance
	--logprint(log_domain, function_name..": START. filename=", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--logs
	--logprint(log_domain, function_name..": for filename=", filename, " get_inode_from_filename returned =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
	--if there is no inode
	if not inode then
		--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
		--logprint(log_domain, function_name..": END. no inode found, returning ENOENT")
		return ENOENT
	end
	--copies all metadata into the variable x
	local x = inode.meta
	--flushes all logs
	--last_logprint(log_domain, function_name..": END")
	--returns 0 (successful), mode, inode number, device, number of links, userID, groupID, size, access time, modif time, inode change time
	return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime
end


--logs start
logprint("MAIN_OP", "MAIN: starting SPLAYFUSE")
--takes userID, groupID, etc., from FUSE context
local uid,gid,pid,puid,pgid = fuse.context()
--logs
logprint("MAIN_OP", "MAIN: FUSE context taken")
--looks if the root_inode is already in the DB
local root_inode = get_inode(1)
--logs
logprint("MAIN_OP", "MAIN: got root_inode")
--if there isn't any
if not root_inode then
	--logs
	logprint("FILE_INODE_OP", "MAIN: creating root")
	--creats a root inode
	root_inode = {
		--metadata
		meta = {
			--inode number is 1
			ino = 1,
			--attributes greatest inode number and greatest block number (TODO remove these attributes)
			xattr ={greatest_inode_n=1, greatest_block_n=0},
			--mode is 755 + is a dir
			mode  = mk_mode(7,5,5) + S_IFDIR,
			--number of links = 2, etc...
			nlink = 2, uid = puid, gid = pgid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time()
		},
		--content is empty
		content = {}
	}
	--logs
	--logprint("FILE_INODE_OP", "MAIN: going to put root file")
	--puts root file element
	put_file("/", 1)
	--logs
	--logprint("FILE_INODE_OP", "MAIN: going to put root inode")
	--puts root inode element
	put_inode(1, root_inode)
end

--the splayfuse object, with all the FUSE methods
local splayfuse = {

--function pulse: used in Lua memFS for "pinging"
pulse = function()
	--logs entrance
	--last_logprint("FILE_MISC_OP", "pulse: START.")
end,

--function getattr: gets the attributes of a requested file
getattr = function(self, filename)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "getattr"
	local log_domain, function_name = "FILE_MISC_OP", "getattr"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--if there is no inode
	if not inode then
		--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
		--last_logprint(log_domain, function_name..": END. no inode found, returns ENOENT")
		return ENOENT
	end
	--logs
	logprint(log_domain, function_name..": for filename=", filename, " get_inode_from_filename returned=")
	--logs the inode
	logprint(log_domain, tbl2str("inode", 0, inode))
	--flushes all logs
	last_logprint(log_domain, function_name..": END.")
	--copies the metadata into the variable x
	local x = inode.meta
	--returns 0 (successful), mode, inode number, device, number of links, userID, groupID, size, access time, modif time, inode change time
	return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime
end,

--function opendir: opens a directory
opendir = function(self, filename)
	--for all the logprint functions: the log domain is "DIR_OP" and the function name is "opendir"
	local log_domain, function_name = "DIR_OP", "opendir"
	--logs entrance
	logprint(log_domain, function_name..": START. filename =", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--if there is no inode, returns the error code ENOENT (No such file or directory)
	if not inode then
		--last_logprint(log_domain, function_name..": END. no inode found, returns ENOENT")
		return ENOENT
	end
	--logs
	--logprint(log_domain, function_name..": for filename =", filename, "get_inode_from_filename returned=")
	--logs the inode
	--logprint(log_domain, tbl2str("inode", 0, inode))
	--flushes all logs
	--last_logprint(log_domain, function_name..": END.")
	--returns 0, and the inode object
	return 0, inode
end,

readdir = function(self, filename, offset, inode)
	--for all the logprint functions: the log domain is "DIR_OP" and the function name is "readdir"
	local log_domain, function_name = "DIR_OP", "readdir"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename, ", offset=", offset)
	--looks for the inode; we don't care about the inode on memory (sequential operations condition)
	local inode = get_inode_from_filename(filename)
	--logs
	--logprint(log_domain, function_name..": inode retrieved =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
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
	--returns 0 and the list of files
	return 0, out
end,

--function releasedir: closes a directory
releasedir = function(self, filename, inode)
	--logs entrance
	logprint("DIR_OP", "releasedir: START. filename=", filename)
	--last_logprint("DIR_OP", tbl2str("inode", 0, inode))
	--returns 0
	return 0
end,

--function mknod: not sure what it does, it creates a generic node? when is this called?
mknod = function(self, filename, mode, rdev)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "mknod"
	local log_domain, function_name = "FILE_MISC_OP", "mknod"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--if the inode does not exist, it can be created
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
		--increments by 1 the "greatest inode number" in the root inode
		root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
		--uses a variable to hold the greatest inode number, so we don't have to look in root_inode.meta.xattr all the time
		local greatest_ino = root_inode.meta.xattr.greatest_inode_n
		--takes userID, groupID, and processID from FUSE context
		local uid, gid, pid = fuse.context()
		--creates an empty inode
		inode = {
			meta = {
				xattr = {},
				--takes the greatest inode number property from the root inode
				ino = greatest_ino,
				mode = mode,
				dev = rdev,
				--number of links is 1
				nlink = 1, uid = uid, gid = gid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time()
			},
			--content is an empty string TODO: MAYBE THIS IS REALLY EMPTY
			content = {""}
		}
		--logs
		--logprint(log_domain, function_name..": what is parent_parent?=", parent.parent)
		--adds the entry in the parent's inode
		parent.content[base]=true
		--puts the parent's inode (changed because it has one more entry)
		local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
		--puts the inode itself
		local ok_put_inode = put_inode(greatest_ino, inode)
		--puts a file that points to that inode
		local ok_put_file = put_file(filename, greatest_ino)
		--puts the root inode, since the greatest inode number changed
		local ok_put_root_inode = put_inode(1, root_inode)
		--returns 0 and the inode
		return 0, inode
	end
end,

--function read: reads data from an open file. TODO: CHANGE MDATE and ADATE WHEN WRITING
read = function(self, filename, size, offset, inode)
	--for all the logprint functions: the log domain is "READ_WRITE_OP" and the function name is "read"
	local log_domain, function_name = "READ_WRITE_OP", "read"
	--logs entrance/timestamp logging
	local start_time = misc.time()
	logprint(log_domain, function_name..": START. elapsed_time=0")
	--logprint(log_domain, function_name..": filename=", filename..", size=", size..", offset=", offset)
	--gets inode from DB
	local inode = get_inode_from_filename(filename)
	--logs
	--logprint(log_domain, function_name..": inode retrieved =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
	--if there is no inode, returns 1
	if not inode then
		return 1
	end
	--timestamp logging
	--logprint(log_domain, function_name..": inode retrieved. elapsed_time="..(misc.time()-start_time))

	--calculates the starting block ID
	local start_block_idx = math.floor(offset / block_size)+1
	--calculates the offset on the starting block
	local rem_start_offset = offset % block_size
	--calculates the end block ID
	local end_block_idx = math.floor((offset+size-1) / block_size)+1
	--calculates the offset on the end block
	local rem_end_offset = (offset+size-1) % block_size

	--logs
	--logprint(log_domain, function_name..": offset=", offset..", size=", size..", start_block_idx=", start_block_idx)
	--logprint(log_domain, function_name..": rem_start_offset=", rem_start_offset..", end_block_idx=", end_block_idx..", rem_end_offset=", rem_end_offset)
	--logprint(log_domain, function_name..": about to get block", {block_n = inode.content[start_block_idx]})
	--timestamp logging
	--logprint(log_domain, function_name..": orig_size et al. calculated, size="..size..". elapsed_time="..(misc.time()-start_time))
	--gets the first block; if the result of the get OP is empty, fills it out with an empty string
	local block = get_block(inode.content[start_block_idx]) or ""
	--table that contains the data, then it gets concatenated (just a final concatenation shows better performance than concatenating inside the loop)
	local data_t = {}
	--timestamp logging
	--logprint(log_domain, function_name..": first block retrieved. elapsed_time="..(misc.time()-start_time))
	--if the starting block and the end block are the same, it does nothing but logging (the first block was retrieved above)
	if start_block_idx == end_block_idx then
		--logs
		--logprint(log_domain, function_name..": just one block to read")
		--timestamp logging
		table.insert(data_t, string.sub(block, rem_start_offset+1, rem_end_offset))
	--if not
	else
		--logs
		--logprint(log_domain, function_name..": several blocks to read")
		table.insert(data_t, string.sub(block, rem_start_offset+1))
		--for all blocks, from the second to the second last one
		for i=start_block_idx+1,end_block_idx-1 do
			--timestamp logging
			--logprint(log_domain, function_name..": getting new block. elapsed_time="..(misc.time()-start_time))
			--gets the block
			block = get_block(inode.content[i]) or ""
			--inserts the block in data_t
			table.insert(data_t, block)
		end
		--timestamp logging
		--logprint(log_domain, function_name..": getting new block. elapsed_time="..(misc.time()-start_time))
		--gets last block
		block = get_block(inode.content[end_block_idx]) or ""
		--inserts it only until the offset
		table.insert(data_t, string.sub(block, 1, rem_end_offset))
	end
	--flushes all timestamp logs
	--last_logprint(log_domain, function_name..": END. elapsed_time="..(misc.time()-start_time))
	--returns 0 and the concatenation of the data table
	return 0, table.concat(data_t)
end,

--function write: writes data into a file. TODO: CHANGE MDATE and ADATE WHEN WRITING
write = function(self, filename, buf, offset, inode)
	--for all the logprint functions: the log domain is "READ_WRITE_OP" and the function name is "write"
	local log_domain, function_name = "READ_WRITE_OP", "write"
	--logs entrance/timestamp logging
	local start_time = misc.time()
	logprint(log_domain, function_name..": START. filename=", filename, "elapsed_time=0")
	--gets inode from the DB
	local inode = get_inode_from_filename(filename)
	--logs
	--logprint(log_domain, function_name..": inode retrieved =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
	--timestamp logging
	--logprint(log_domain, function_name..": inode retrieved. elapsed_time="..(misc.time()-start_time))
	--stores the size reported by the inode in the variable orig_size
	local orig_size = inode.meta.size
	--size is initially equal to the size of the buffer
	local size = #buf
	--calculates the starting block ID
	local start_block_idx = math.floor(offset / block_size)+1
	--calculates the offset on the starting block
	local rem_start_offset = offset % block_size
	--calculates the end block ID
	local end_block_idx = math.floor((offset+size-1) / block_size)+1
	--calculates the offset on the end block
	local rem_end_offset = ((offset+size-1) % block_size)
	--logs
	logprint(log_domain, function_name..": orig_size=", orig_size..", offset=", offset..", size=", size..", start_block_idx=", start_block_idx)
	logprint(log_domain, function_name..": rem_start_offset=", rem_start_offset..", end_block_idx=", end_block_idx..", rem_end_offset=", rem_end_offset)
	logprint(log_domain, function_name..": about to get block. block_id=", inode.content[start_block_idx])
	--timestamp logging
	logprint(log_domain, function_name..": orig_size et al. calculated, size="..size..". elapsed_time="..(misc.time()-start_time))
	--block, block_id and to_write_in_block are initialized to nil
	local block, block_id, to_write_in_block
	--initializes the block offset as the offset in the starting block
	local block_offset = rem_start_offset
	--calculates if the size of the file changed; if the offset+size is bigger than the original size, yes.
	local size_changed = ((offset+size) > orig_size)
	--initializes the remaining buffer as the whole buffer
	local remaining_buf = buf
	--timestamp logging
	--logprint(log_domain, function_name..": calculated more stuff. elapsed_time="..(misc.time()-start_time))
	--timestamp logging
	--logprint(log_domain, function_name..": root might have been retrieved. elapsed_time="..(misc.time()-start_time))
	--logs
	logprint(log_domain, function_name..": new file is bigger? size_changed="..tostring(size_changed))
	logprint(log_domain, function_name..": buf=\""..buf.."\"")
	--for all blocks from the starting to the end block
	for i=start_block_idx, end_block_idx do
		--logs
		logprint(log_domain, function_name..": im in the for loop, i=", i)
		--if the block exists
		if inode.content[i] then
			--logs
			logprint(log_domain, function_name..": block exists, so get the block")
			--gets the block; the block_id is the ith entry of inode contents table
			block = get_block(inode.content[i])
			--removes the block from the content table
			table.remove(inode.content, i)
		--if not
		else
			--logs
			logprint(log_domain, function_name..": block doesnt exists, so create the block")
			--the block initially is an empty string
			block = ""
		end
		--logs
		logprint(log_domain, function_name..": remaining_buf=\""..remaining_buf.."\"")
		logprint(log_domain, function_name..": (#remaining_buf+block_offset)=", (#remaining_buf+block_offset))
		logprint(log_domain, function_name..": block_size=", block_size)
		--if the size of the remaining buffer + the block offset is bigger than a full block size (it means we need to trunk the remaining buffer cause it does not fit in one block)
		if (#remaining_buf+block_offset) > block_size then
			--logs
			logprint(log_domain, function_name..": more than block size")
			--fills out to_write_in_block with enough data to reach the end of the block
			to_write_in_block = string.sub(remaining_buf, 1, (block_size - block_offset))
			--cuts that data from the remaining buffer
			remaining_buf = string.sub(remaining_buf, (block_size - block_offset)+1, -1)
		--if not (all the remaining buffer fits in the block)
		else
			--logs
			logprint(log_domain, function_name..": less than block size")
			--to_write_in_block is equal to the remaining buffer
			to_write_in_block = remaining_buf
		end
		--logs
		logprint(log_domain, function_name..": block=\""..block.."\"")
		logprint(log_domain, function_name..": to_write_in_block=\""..to_write_in_block.."\"")
		logprint(log_domain, function_name..": block_offset=", block_offset..", size of to_write_in_block=", #to_write_in_block)
		--inserts the to_write_in_block segment into the block. TODO: CHECK IF THE +1 AT THE END IS OK
		block = string.sub(block, 1, block_offset)..to_write_in_block..string.sub(block, (block_offset + #to_write_in_block + 1))
		--logs
		logprint(log_domain, function_name..": now block=", block)
		--timestamp logging
		--logprint(log_domain, function_name..": before putting the block. elapsed_time="..(misc.time()-start_time))
		--the blockID is the hash of the inode number concatenated with the block data
		block_id = hash_string(tostring(inode.meta.ino)..block)
		--puts the block. TODO: delete the other block if existed through GC
		put_block(block_id, block)
		--timestamp logging
		--logprint(log_domain, function_name..": after putting the block. elapsed_time="..(misc.time()-start_time))
		--inserts the new block number in the contents table
		table.insert(inode.content, block_id)
		--the block offset is set to 0
		block_offset = 0
		--timestamp logging
		--logprint(log_domain, function_name..": timestamp at the end of each cycle. elapsed_time="..(misc.time()-start_time))
	end
	--if the size changed
	if size_changed then
		--changes the metadata in the inode
		inode.meta.size = offset+size
		--puts the inode into the DB
		put_inode(inode.meta.ino, inode)
		--logs
		logprint(log_domain, function_name..": inode was written. elapsed_time="..(misc.time()-start_time))
	end
	--flushes all timestamp loggings
	--last_logprint(log_domain, function_name..": END. elapsed_time="..(misc.time()-start_time))
	--returns the size of the written buffer
	return #buf
end,

--function open: opens a file for read/write operations
--NOTE: WHEN DOING ATOMIC WRITE READ, LONG SESSIONS WITH THE LIKES OF OPEN HAVE NO SENSE.
--TODO: CHECK ABOUT MODE AND USER RIGHTS.
open = function(self, filename, mode)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "open"
	local log_domain, function_name = "FILE_MISC_OP", "open"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--m is the remainder mode divided by 4
	local m = mode % 4
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--[[
	--NOTE: CODE RELATED TO SESSION ORIENTED MODE
	if not inode then return ENOENT end
	inode.open = (inode.open or 0) + 1
	put_inode(inode.meta.ino, inode)
	--TODO: CONSIDER CHANGING A FIELD OF THE DISTDB WITHOUT RETRIEVING THE WHOLE OBJECT; DIFFERENTIAL WRITE
	--]]
	--returns 0 and the inode
	return 0, inode
end,

--function release: closes an open file
--NOTE: RELEASE DOESNT MAKE SENSE WHEN USING ATOMIC READ WRITES
release = function(self, filename, inode)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "release"
	local log_domain, function_name = "FILE_MISC_OP", "release"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)

	--[[
	--NOTE: CODE RELATED TO SESSION ORIENTED MODE
	inode.open = inode.open - 1
	--logprint(log_domain, function_name..": for filename=", filename, {inode_open=inode.open})
	if inode.open < 1 then
		--logprint(log_domain, function_name..": open < 1")
		if inode.changed then
			--logprint(log_domain, function_name..": going to put")
			local ok_put_inode = put_inode(inode.ino, inode)
		end
		if inode.meta_changed then
			--logprint(log_domain, function_name..": going to put")
			local ok_put_inode = put_inode(inode.ino, inode)
		end
		--logprint(log_domain, function_name..": meta_changed = nil")
		inode.meta_changed = nil
		--logprint(log_domain, function_name..": changed = nil")
		inode.changed = nil
	end
	--]]
	--returns 0
	return 0
end,

--function fgetattr:
--TODO: CHECK IF fgetattr IS USEFUL, IT IS! TODO: CHECK WITH filename
fgetattr = function(self, filename, inode, ...)
	--logs entrance
	logprint("FILE_MISC_OP", "fgetattr: START. filename=", filename)
	--last_logprint("FILE_MISC_OP", tbl2str("inode", 0, inode))
	--returns the attributes of a file
	return get_attributes(filename)
end,

--function rmdir: removes a directory from the filesystem
rmdir = function(self, filename)
	--for all the logprint functions: the log domain is "DIR_OP" and the function name is "rmdir"
	local log_domain, function_name = "DIR_OP", "rmdir"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--gets the inode
	local inode_n = get_inode_n(filename)
	--if the inode exists. TODO: if it doesn't exist, should we still return 0? when we know this, change the model to "if not smth then return error end, continue and return (no else)"
	if inode_n then
		--splits the filename
		local dir, base = filename:splitfilename()
		--logs
		--logprint(log_domain, function_name..": got inode", {inode, inode})
		--gets the parent dir inode
		local parent = get_inode_from_filename(dir)
		--deletes the entry from the contents of the parent node. TODO: CHECK WHAT HAPPENS WHEN TRYING TO ERASE A NON-EMPTY DIR
		parent.content[base] = nil
		--decrements the number of links in the parent node (one less dir pointing to it with the ".." element)
		parent.meta.nlink = parent.meta.nlink - 1
		--removes the file from the DB
		delete_file(filename)
		--removes the inode from the DB
		delete_dir_inode(inode_n)
		--updates the parent inode
		put_inode(parent.ino, parent)
	end
	--returns 0
	return 0
end,

--function mkdir: creates a directory
--TODO: CHECK WHAT HAPPENS WHEN TRYING TO MKDIR A DIR THAT EXISTS
--TODO: MERGE THESE CODES (MKDIR, MKNODE, CREATE) ON 1 FUNCTION
mkdir = function(self, filename, mode, ...)
	--for all the logprint functions: the log domain is "DIR_OP" and the function name is "mkdir"
	local log_domain, function_name = "DIR_OP", "mkdir"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--tries to get the inode first
	local inode = get_inode_from_filename(filename)
	--if there is no inode, we can create it
	if not inode then
		--splits the filename
		local dir, base = filename:splitfilename()
		--gets the parent dir inode
		local parent = get_inode_from_filename(dir)
		--initializes root_inode as nil
		local root_inode = nil
		--if the parent inode number is 1
		if parent.meta.ino == 1 then
			--the root inode is equal to the parent (like this, there is no need to do another read transaction)
			root_inode = parent
		--if not
		else
			--gets the inode from the DB
			root_inode = get_inode(1)
		end
		--increments by 1 the "greatest inode number" in the root inode
		root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
		--takes the greatest inode number and stores it in greatest_ino
		local greatest_ino = root_inode.meta.xattr.greatest_inode_n
		--takes userID, groupID, and processID from FUSE context
		local uid, gid, pid = fuse.context()
		--creates an empty dir inode
		inode = {
			meta = {
				xattr = {},
				mode = set_bits(mode, S_IFDIR),
				ino = greatest_ino,
				--deviceID is 0. TODO: CHECK IF USEFUL
				dev = 0,
				--number of links is 2. TODO: CHECK IF SIZE IS NOT block_size
				nlink = 2, uid = uid, gid = gid, size = 0, atime = os.time(), mtime = os.time(), ctime = os.time()
			},
			content = {}
		}
		--adds the entry into the parent contents table
		parent.content[base]=true
		--adds one link to the parent (the ".." link)
		parent.meta.nlink = parent.meta.nlink + 1

		--puts the parent's inode, because the contents changed
		local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
		--puts the inode, because it's new
		local ok_put_inode = put_inode(greatest_ino, inode)
		--puts the file, because it's new
		local ok_put_file = put_file(filename, greatest_ino)
		--puts root inode, because greatest ino was incremented
		local ok_put_root_inode = put_inode(1, root_inode)
	end
	--returns 0
	return 0
end,

--function create: creates and opens a file
create = function(self, filename, mode, flag, ...)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "create"
	local log_domain, function_name = "FILE_MISC_OP", "create"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--gets inode from the DB
	local inode = get_inode_from_filename(filename)
	--if the inode doesn't exist
	if not inode then
		--splits the filename
		local dir, base = filename:splitfilename()
		--gets the parent dir inode
		local parent = get_inode_from_filename(dir)
		--initializes the root inode as nil
		local root_inode = nil
		--if the parent is the root node
		if parent.meta.ino == 1 then
			--root_inode is equal to the parent (no need to look for it again)
			root_inode = parent
		--if not
		else
			--gets the root inode
			root_inode = get_inode(1)
		end
		--increments by 1 the "greatest inode number" in the root inode
		root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
		--assigns that number to greatest_ino
		local greatest_ino = root_inode.meta.xattr.greatest_inode_n
		--takes userID, groupID, and processID from FUSE context
		local uid, gid, pid = fuse.context()
		--creates an empty inode
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
		--adds the entry in the parent dir inode
		parent.content[base]=true

		--puts the parent's inode, because the contents changed
		local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
		--puts the inode, because it's new
		local ok_put_inode = put_inode(greatest_ino, inode)
		--puts the file, because it's new
		local ok_put_file = put_file(filename, greatest_ino)
		--puts root inode, because greatest ino was incremented
		local ok_put_root_inode = put_inode(1, root_inode)
		--returns 0 and the inode element
		return 0, inode
	end
end,

--function flush: cleans local record about an open file
flush = function(self, filename, inode)
	--logs entrance
	logprint("FILE_MISC_OP", "flush: START. filename=", filename)
	--if the inode changed
	if inode.changed then
		--TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
	end
	--returns 0
	return 0
end,

--function readlink: reads a symbolic link
readlink = function(self, filename)
	--logs entrance
	logprint("LINK_OP", "readlink: START. filename=", filename)
	--gets inode from the DB
	local inode = get_inode_from_filename(filename)
	--if there is an inode, returns 0, and the symbolic link
	if inode then
		return 0, inode.content[1]
	end
	--if not, returns ENOENT
	return ENOENT
end,

--function symlink: makes a symbolic link
symlink = function(self, from, to)
	--for all the logprint functions: the log domain is "LINK_OP" and the function name is "symlink"
	local log_domain, function_name = "LINK_OP", "symlink"
	--logs entrance
	logprint(log_domain, function_name..": START. from=", from, "to=", to)
	--splits the "to" filename
	local to_dir, to_base = to:splitfilename()
	--gets the  parent dir of the "to" file
	local to_parent = get_inode_from_filename(to_dir)

	--initializes the root inode as nil
	local root_inode = nil
	--if the parent is the root node
	if to_parent.meta.ino == 1 then
		--root_inode is equal to the parent (no need to look for it again)
		root_inode = to_parent
	--if not
	else
		--gets the root inode
		root_inode = get_inode(1)
	end
	--logs
	--logprint(log_domain, function_name..": root_inode retrieved",{root_inode=root_inode})
	--increments by 1 the "greatest inode number" in the root inode
	root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
	--assigns that value to greatest_ino
	local greatest_ino = root_inode.meta.xattr.greatest_inode_n
	--takes userID, groupID, and processID from FUSE context
	local uid, gid, pid = fuse.context()
	--creates an empty inode
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
	--adds the entry into the parent dir inode of the "to" file
	to_parent.content[to_base]=true

	--puts the to_parent's inode, because the contents changed
	local ok_put_to_parent_inode = put_inode(to_parent.meta.ino, to_parent)
	--puts the to_inode, because it's new
	local ok_put_inode = put_inode(greatest_ino, to_inode)
	--puts the file, because it's new
	local ok_put_file = put_file(to, greatest_ino)
	--puts root inode, because greatest ino was incremented
	local ok_put_root_inode = put_inode(1, root_inode)
	--returns 0. TODO: this return 0 was inside an IF
	return 0
end,

--function rename: moves/renames a file
rename = function(self, from, to)
	--for all the logprint functions: the log domain is "MV_CP_OP" and the function name is "rename"
	local log_domain, function_name = "MV_CP_OP", "rename"
	--logs entrance
	logprint(log_domain, function_name..": START. from=", from..", to=", to)
	--if the "from" file is equal to the "to" file
	if from == to then return 0 end
	--gets the "from" inode
	local from_inode = get_inode_from_filename(from)
	--if there is a from inode
	if from_inode then
		--logs
		--logprint(log_domain, function_name..": entered in IF", {from_inode=from_inode})
		--splits the "from" filename
		local from_dir, from_base = from:splitfilename()
		--splits the "to" filename
		local to_dir, to_base = to:splitfilename()
		--gets the parent dir inode of the "from" file
		local from_parent = get_inode_from_filename(from_dir)
		--initializes the parent dir inode of the "to" file as nil
		local to_parent = nil
		--if the "to" and "from" parent dir inodes are the same
		if to_dir == from_dir then
			--to_parent is the from_parent (no need to look it up again)
			to_parent = from_parent
		--if not
		else
			--gets the "to" parent dir inode
			to_parent = get_inode_from_filename(to_dir)
		end
		--adds the entry into the "to" parent dir inode
		to_parent.content[to_base] = true
		--deletes the entry from the "from" parent dir inode
		from_parent.content[from_base] = nil
		--logs
		--logprint(log_domain, function_name..": changes made", {to_parent=to_parent, from_parent=from_parent})
		--only if "to" and "from" are different (avoids writing on parent's inode twice, for the sake of efficiency)
		if to_dir ~= from_dir then
			--updates the to_parent dir inode, because the contents changed
			local ok_put_to_parent_inode = put_inode(to_parent.meta.ino, to_parent)
		end
		--puts the from_parent's inode, because the contents changed
		local ok_put_from_parent_inode = put_inode(from_parent.meta.ino, from_parent)
		--puts the to_file, because it's new
		local ok_put_file = put_file(to, from_inode.meta.ino)
		--deletes the from_file
		local ok_delete_file = delete_file(from)
		--returns 0
		return 0
	end
end,

--function link: makes a hard link
link = function(self, from, to, ...)
	--for all the logprint functions: the log domain is "LINK_OP" and the function name is "link"
	local log_domain, function_name = "LINK_OP", "link"
	--logs entrance
	logprint(log_domain, function_name..": START. from=", from..", to=", to)
	--if "from" and "to" are the same, do nothing; return 0
	if from == to then return 0 end
	--gets the "from" inode
	local from_inode = get_inode_from_filename(from)
	--logs
	--logprint(log_domain, function_name..": from_inode", {from_inode=from_inode})
	--if the "from" inode exists
	if from_inode then
		--logs
		--logprint(log_domain, function_name..": entered in IF")
		--splits the "to" filename
		local to_dir, to_base = to:splitfilename()
		--logs
		--logprint(log_domain, function_name..": to_dir=", to_dir..", to_base=", to_base)
		--gets the parent dir inode of the "to" file
		local to_parent = get_inode_from_filename(to_dir)
		--logs
		--logprint(log_domain, function_name..": to_parent", {to_parent=to_parent})
		--adds an entry to the "to" parent dir inode
		to_parent.content[to_base] = true
		--logs
		--logprint(log_domain, function_name..": added file in to_parent", {to_parent=to_parent})
		--increments the number of links in the inode
		from_inode.meta.nlink = from_inode.meta.nlink + 1
		--logs
		--logprint(log_domain, function_name..": incremented nlink in from_inode", {from_inode=from_inode})

		--puts the to_parent's inode, because the contents changed
		local ok_put_to_parent = put_inode(to_parent.meta.ino, to_parent)
		--puts the inode, because nlink was incremented
		local ok_put_inode = put_inode(from_inode.meta.ino, from_inode)
		--puts the to_file, because it's new
		local ok_put_file = put_file(to, from_inode.meta.ino)
		--returns 0
		return 0
	end
end,

--function unlink: deletes a link to a inode
unlink = function(self, filename, ...)
	--for all the logprint functions: the log domain is "LINK_OP" and the function name is "unlink"
	local log_domain, function_name = "LINK_OP", "unlink"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)
	--gets the inode
	local inode = get_inode_from_filename(filename)
	--if the inode exists
	if inode then
		--splits the filename
		local dir, base = filename:splitfilename()
		--gets the parent
		local parent = get_inode_from_filename(dir)
		--logs
		--logprint(log_domain, function_name..":", {parent=parent})
		--deletes the entry in the parent inode
		parent.content[base] = nil
		--logs
		--logprint(log_domain, function_name..": link to file in parent removed", {parent=parent})
		--increments the number of links
		inode.meta.nlink = inode.meta.nlink - 1
		--logs
		--logprint(log_domain, function_name..": now inode has less links =")
		--logprint(log_domain, tbl2str("inode", 0, inode))
		--deletes the file element, because it's being unlinked
		local ok_delete_file = delete_file(filename)
		--puts the parent ino, because the record of the file was deleted
		local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
		--if the inode has no more links
		if inode.meta.nlink == 0 then
			--logprint(log_domain, function_name..": i have to delete the inode too")
			--deletes the inode, since it's not linked anymore
			delete_inode(inode.meta.ino)
		--if not
		else
			--updates the inode
			local ok_put_inode = put_inode(inode.meta.ino, inode)
		end
		--returns 0
		return 0
	--if not
	else
		--logs error
		--logprint(log_domain, function_name..": ERROR no inode")
		--returns ENOENT
		return ENOENT
	end
end,

--function chown: UNTIL HERE I COMMENTED
chown = function(self, filename, uid, gid)
	--logs entrance
	logprint("FILE_MISC_OP", "chown: START. filename=", filename..", uid=", uid..", gid=", gid)

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

chmod = function(self, filename, mode)
	--logs entrance
	logprint("FILE_MISC_OP", "chmod: START. filename=", filename)

	local inode = get_inode_from_filename(filename)
	if inode then
		inode.meta.mode = mode
		local ok_put_inode = put_inode(inode.meta.ino, inode)
		return 0
	else
		return ENOENT
	end
end,

utime = function(self, filename, atime, mtime)
	--logs entrance
	logprint("FILE_MISC_OP", "utime: START. filename=", filename, "atime=", atime, "mtime=", mtime)

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

ftruncate = function(self, filename, size, inode)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "ftruncate"
	local log_domain, function_name = "FILE_MISC_OP", "ftruncate"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename, "size=", size)
	--gets inode from DB
	local inode = get_inode_from_filename(filename)
	--logs
	--logprint(log_domain, function_name..": inode was retrieved =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
	--if there is the inode
	if inode then
		--stores the size reported by the inode in the variable orig_size
		local orig_size = inode.meta.size
		--calculates the index (in the inode contents table) of the block where the pruning takes place
		local block_idx = math.floor((size - 1) / block_size) + 1
		--calculates the offset on the block
		local rem_offset = size % block_size
		--logs
		--logprint(log_domain, function_name..": orig_size=", orig_size..", new_size=", size..", block_idx=", block_idx..", rem_offset=", rem_offset)
		--from the last block until the second last to be deleted (decremented for loop)
		for i=#inode.content, block_idx+1,-1 do
			--logs
			--logprint(log_domain, function_name..": about to remove block number inode.content["..i.."]=", inode.content[i])
			--deletes the block. TODO: for the moment we will not do it, just send them to GC
			--delete_block(inode.content[i])
			table.remove(inode.content, i)
		end
		--logs
		--logprint(log_domain, function_name..": about to change block number inode.content["..block_idx.."]=", inode.content[block_idx])
		--if the remainding offset is 0
		if rem_offset == 0 then
			--logprint(log_domain, function_name..": last block must be empty, so we delete it")
			--deletes the block. TODO: for the moment we will not do it, just send them to GC
			--delete_block(inode.content[block_idx])
			table.remove(inode.content, block_idx)
		--if not, we must truncate the block and rewrite it
		else
			--logs
			--logprint(log_domain, function_name..": last block is not empty")
			local last_block = get_block(block_idx)
			--logprint(log_domain, function_name..": it already has this=", last_block)
			local write_in_last_block = string.sub(last_block, 1, rem_offset)
			--deletes the block. TODO: for the moment we will not do it, just send them to GC
			--delete_block(inode.content[block_idx])
			--logs
			--logprint(log_domain, function_name..": and we change to this=", write_in_last_block)
			--the blockID is the hash of the inode number concatenated with the block data
			local block_id = hash_string(tostring(inode.meta.ino)..write_in_last_block)
			--puts the block.
			put_block(block_id, write_in_last_block)
			--replaces with the new blockID the entry blockIdx in the contents table
			inode.content[block_idx] = block_id
		end

		inode.meta.size = size

		--logprint(log_domain, function_name..": about to write inode")

		put_inode(inode.meta.ino, inode)

		return 0
	else
		return ENOENT
	end
end,

truncate = function(self, filename, size)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "truncate"
	local log_domain, function_name = "FILE_MISC_OP", "truncate"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename, "size=", size)
	--gets inode from DB
	local inode = get_inode_from_filename(filename)
	--logs
	--logprint(log_domain, function_name..": inode was retrieved =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
	--if there is the inode
	if inode then
		--stores the size reported by the inode in the variable orig_size
		local orig_size = inode.meta.size
		--calculates the index (in the inode contents table) of the block where the pruning takes place
		local block_idx = math.floor((size - 1) / block_size) + 1
		--calculates the offset on the block
		local rem_offset = size % block_size
		--logs
		--logprint(log_domain, function_name..": orig_size=", orig_size..", new_size=", size..", block_idx=", block_idx..", rem_offset=", rem_offset)
		--from the last block until the second last to be deleted (decremented for loop)
		for i=#inode.content, block_idx+1,-1 do
			--logs
			--logprint(log_domain, function_name..": about to remove block number inode.content["..i.."]=", inode.content[i])
			--deletes the block. TODO: for the moment we will not do it, just send them to GC
			--delete_block(inode.content[i])
			table.remove(inode.content, i)
		end
		--logs
		--logprint(log_domain, function_name..": about to change block number inode.content["..block_idx.."]=", inode.content[block_idx])
		--if the remainding offset is 0
		if rem_offset == 0 then
			--logprint(log_domain, function_name..": last block must be empty, so we delete it")
			--deletes the block. TODO: for the moment we will not do it, just send them to GC
			--delete_block(inode.content[block_idx])
			table.remove(inode.content, block_idx)
		--if not, we must truncate the block and rewrite it
		else
			--logs
			--logprint(log_domain, function_name..": last block is not empty")
			local last_block = get_block(block_idx)
			--logprint(log_domain, function_name..": it already has this=", last_block)
			local write_in_last_block = string.sub(last_block, 1, rem_offset)
			--deletes the block. TODO: for the moment we will not do it, just send them to GC
			--delete_block(inode.content[block_idx])
			--logs
			--logprint(log_domain, function_name..": and we change to this=", write_in_last_block)
			--the blockID is the hash of the inode number concatenated with the block data
			local block_id = hash_string(tostring(inode.meta.ino)..write_in_last_block)
			--puts the block.
			put_block(block_id, write_in_last_block)
			--replaces with the new blockID the entry blockIdx in the contents table
			inode.content[block_idx] = block_id
		end

		inode.meta.size = size

		--logprint(log_domain, function_name..": about to write inode")

		put_inode(inode.meta.ino, inode)

		return 0
	else
		return ENOENT
	end
end,

access = function(...)
	--logs entrance
	logprint("FILE_MISC_OP", "access: START.")
	
	return 0
end,

fsync = function(self, filename, isdatasync, inode)
	--logs entrance
	logprint("FILE_MISC_OP", "fsync: START. filename=", filename)
	--TODO: PA DESPUES
	--[[
	mnode.flush_node(inode, filename, false) 
	if isdatasync and inode.changed then 
		mnode.flush_data(inode.content, inode, filename) 
	end
	--]]
	return 0
end,

fsyncdir = function(self, filename, isdatasync, inode)
	--logs entrance
	logprint("FILE_MISC_OP", "fsyncdir: START. filename=", filename)

	return 0
end,

listxattr = function(self, filename, size)
	--logs entrance
	logprint("FILE_MISC_OP", "listxattr: START. filename=", filename)

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

removexattr = function(self, filename, name)
	--logs entrance
	logprint("FILE_MISC_OP", "removexattr: START. filename=", filename)

	local inode = get_inode_from_filename(filename)
	if inode then
		inode.meta.xattr[name] = nil
		local ok_put_inode = put_inode(inode.meta.ino, inode)
		return 0
	else
		return ENOENT
	end
end,

setxattr = function(self, filename, name, val, flags)
	--logs entrance
	logprint("FILE_MISC_OP", "setxattr: START. filename=", filename)

	--string.hex = function(s) return s:gsub(".", function(c) return format("%02x", string.byte(c)) end) end
	local inode = get_inode_from_filename(filename)
	if inode then
		inode.meta.xattr[name]=val
		local ok_put_inode = put_inode(inode.meta.ino, inode)
		return 0
	else
		return ENOENT
	end
end,

getxattr = function(self, filename, name, size)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "getxattr"
	local log_domain, function_name = "FILE_MISC_OP", "getxattr"
	--logs entrance
	logprint(log_domain, function_name..": START. filename=", filename)

	local inode = get_inode_from_filename(filename)
	--logprint(log_domain, function_name..": get_inode was successful =")
	--logprint(log_domain, tbl2str("inode", 0, inode))
	if inode then
		--logprint(log_domain, function_name..": retrieving xattr["..name.."]=", {inode_meta_xattr=inode.meta.xattr[name]})
		return 0, inode.meta.xattr[name] or "" --not found is empty string
	else
		return ENOENT
	end
end,

statfs = function(self,filename)
	local inode,parent = get_inode_from_filename(filename)
	local o = {bs=block_size,blocks=64,bfree=48,bavail=48,bfiles=16,bffree=16}
	return 0, o.bs, o.blocks, o.bfree, o.bavail, o.bfiles, o.bffree
end
}

--profiler.start()

--logprint("MAIN_OP", "MAIN: before defining fuse_opt")

fuse_opt = { 'splayfuse', 'mnt', '-f', '-s', '-d', '-oallow_other'}

--logprint("MAIN_OP", "MAIN: fuse_opt defined")

if select('#', ...) < 2 then
	print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
	os.exit(1)
end

--logprint("MAIN_OP", "MAIN: going to execute fuse.main")

fuse.main(splayfuse, {...})
--events.run(function()
--	fuse.main(splayfuse, {"testsplayfuse","/home/unine/testsplayfuse/testsplayfuse/","-ouse_ino,big_writes","d"})
--end)
--profiler.stop()
