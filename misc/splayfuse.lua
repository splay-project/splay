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
--standard error codes (errno.h)
local ENOENT = -2
local ENOTEMPTY = -39
local ENOSYS = -38
--consistency types can be "evtl_consistent", "paxos" or "consistent"
local IBLOCK_CONSIST = "consistent"
local DBLOCK_CONSIST = IBLOCK_CONSIST
local BLOCK_CONSIST = "consistent"
--the URL of the Entry Point to the distDB
local DB_URL = "127.0.0.1:15272"


--LOCAL VARIABLES

local block_size = 48
local blank_block = string.rep("\0", block_size)
--TODO: what is this for? check in memfs
local open_mode = {'rb','wb','rb+'}
local session_id = nil
local seq_number = 0


--LOCAL VARIABLES FOR LOGGING

log_domains.MAIN_OP = true
log_domains.FILE_IBLOCK_OP = true
log_domains.DIR_OP = true
log_domains.LINK_OP = true
log_domains.READ_WRITE_OP = true
log_domains.FILE_MISC_OP = true
log_domains.MV_CP_OP = true


--MISC FUNCTIONS

--function split_filename: splits the filename into parent dir and basename; for example: "/usr/include/lua/5.1/lua.h" -> "/usr/include/lua/5.1", "lua.h"
function split_filename(str)
	local dir,file = str:match("(.-)([^:/\\]*)$")
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
local function decode_acl(acl)
	--logs START of the function
	--last_logprint("FILE_IBLOCK_OP", "decode_acl: START. acl="..acl)
	local version = acl:sub(1,4)
	local n = 5
	while true do
		local tag = acl:sub(n, n + 1)
		local perm = acl:sub(n + 2, n + 3)
		local id = acl:sub(n + 4, n + 7)
		n = n + 8
		if n >= #acl then break end
	end
	--logs END of the function
	--last_logprint("FILE_IBLOCK_OP", "decode_acl: END.")
end

--function mk_mode: creates the mode from the owner, group, world rights and the sticky bit
local function mk_mode(owner, group, world, sticky)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "mk_mode"
	--logs START of the function
	--logprint(log_domain, function_name..": START. owner="..tostring(owner)..", group="..tostring(group)..", world="..tostring(world)..", sticky="..tostring(sticky))
	--result mode is the combination of the owner, group, world rights and the sticky mode
	local result_mode = owner * S_UID + group * S_GID + world + ((sticky or 0) * S_SID)
	--logs END of the function
	--last_logprint(log_domain, function_name..": END. result_mode="..result_mode)
	--returns the mode
	return result_mode
end

local function hash_string(str)
	return crypto.evp.digest("sha1", str)
end

--function generate_iblock_n: generates an iblock number using the sessionID and sequence number
local function generate_iblock_n()
	--logs START of the function
	--logprint("FILE_IBLOCK_OP", "generate_iblock_n: START, session_id="..session_id)
	--increments the seq number
	seq_number = (seq_number + 1) % 1000
	--the iblock number is 1000 times the session id + sequence number
	local iblock_n = (1000 * session_id) + seq_number
	--logs
	--last_logprint("FILE_IBLOCK_OP", "generate_iblock_n: END, seq number=", seq_number, "iblock_n=", iblock_n)
	return iblock_n
end


--FS TO DB FUNCTIONS

--GET FUNCTIONS

--function get_block: gets a block from the DB
local function get_block(block_id)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "get_block"
	--logs START of the function
	logprint(log_domain, function_name..": START. block_id="..tostring(block_id))
	--if the blockID is nil, returns nil
	if not block_id then
		return nil
	end
	--reads the file from the DB
	local ok, block = send_get(DB_URL, block_id, BLOCK_CONSIST)
	--if the reading was not successful
	if not ok then
		--reports the error, flushes all logs and return nil
		--last_logprint(log_domain, function_name..": ERROR, send_get was not OK")
		return nil
	end
	--logs END of the function
	last_logprint(log_domain, function_name..": END. block=\""..tostring(block).."\"")
	--if everything went well, it returns the block data
	return block
end

--function get_iblock: gets an iblock from the DB
local function get_iblock(iblock_n)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "get_iblock"
	--logs START of the function
	--logprint(log_domain, function_name..": START. iblock_n="..tostring(iblock_n))
	--if the iblock is nil, returns nil
	if not iblock_n then
		return nil
	end
	--reads the iblock from the DB
	local ok, iblock_serial = send_get(DB_URL, hash_string("iblock:"..iblock_n), IBLOCK_CONSIST)
	--logs
	--logprint(log_domain, function_name..": send_get returned, ok="..tostring(ok))
	--logprint(log_domain, tbl2str("iblock_serial", 0, iblock_serial))
	--if the reading was not successful
	if not ok then
		--reports the error and returns nil
		--last_logprint(log_domain, function_name..": END. send_get was not OK")
		return nil
	end
	--if the requested record is empty
	if not iblock_serial then
		--reports the error and returns nil
		--last_logprint(log_domain, function_name..": END. iblock_serial is nil, returning nil")
		return nil
	end
	--deserializes the iblock
	local iblock = serializer.decode(iblock_serial)
	--logs
	--logprint(log_domain, function_name..": send_get returned")
	--logs END of the function
	--last_logprint(log_domain, function_name..":END.", tbl2str("iblock", 0, iblock))
	--returns the iblock
	return iblock
end

local get_dblock = get_iblock

--function get_iblock_n: gets an iblock number from the DB, by identifying it with the filename
local function get_iblock_n(filename)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "get_iblock_n"
	--logs START of the function
	--logprint(log_domain, function_name..": START. filename=", filename)
	--reads the file from the DB
	local ok, iblock_n = send_get(DB_URL, hash_string("file:"..filename), IBLOCK_CONSIST)
	--if the reading was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, send_get was not OK")
		return nil
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END. iblock_n=", iblock_n)
	--returns the iblock number
	return tonumber(iblock_n)
end

local get_dblock_n = get_iblock_n

--function get_iblock_from_filename: gets an iblock from the DB, by identifying it with the filename
local function get_iblock_from_filename(filename)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "get_iblock_from_filename"
	--logs START of the function
	--logprint(log_domain, function_name..": START. filename=\""..filename.."\"")
	--the iblock number is extracted by calling get_iblock_n
	local iblock_n = get_iblock_n(filename)
	--logs END of the function
	--last_logprint(log_domain, function_name..": END. iblock_n="..tostring(iblock_n))
	--returns the corresponding iblock
	return get_iblock(iblock_n)
end

local get_dblock_from_filename = get_iblock_from_filename

--PUT FUNCTIONS

--function put_block: puts a block into the DB
local function put_block(block_id, block)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "put_block"
	--logs START of the function
	logprint(log_domain, function_name..": START. block_id="..block_id..", block_size="..string.len(block))
	--writes the block in the DB
	local ok = send_put(DB_URL, block_id, BLOCK_CONSIST, block)
	--if the writing was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, send_put was not OK")
		return nil
	end
	--logs END of the function
	last_logprint(log_domain, function_name..": END")
	--returns the blockID
	return true
end

--function put_iblock: puts an iblock into the DB
local function put_iblock(iblock_n, iblock)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "put_iblock"
	--logs START of the function
	--logprint(log_domain, function_name..": START. iblock_n=", iblock_n)
	--logprint(log_domain, tbl2str("iblock", 0, iblock))

	--writes the iblock in the DB
	local ok = send_put(DB_URL, hash_string("iblock:"..iblock_n), IBLOCK_CONSIST, serializer.encode(iblock))
	--logs END of the function
	--last_logprint(log_domain, function_name..": END. successful="..tostring(ok))
	--returns the result of the send_put
	return ok
end

local put_dblock = put_iblock

--function put_file: puts a file into the DB
local function put_file(filename, iblock_n)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "put_file"
	--checks input errors
	--if filename is not a string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, filename not a string")
		return nil
	end
	--if iblock_n is not a number
	if type(iblock_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, iblock_n not a number")
		return nil
	end
	--logs START of the function
	--logprint(log_domain, function_name..": START. filename=", filename, "iblock_n=", iblock_n)

	--writes the file in the DB
	local ok = send_put(DB_URL, hash_string("file:"..filename), IBLOCK_CONSIST, iblock_n)
	--if the writing was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, send_put was not OK")
		return nil
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--DELETE FUNCTIONS

--function del_block: deletes a block from the DB
local function del_block(block_id)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "del_block"
	--logs START of the function
	--logprint(log_domain, function_name..": START. block_n=", block_n)
	--deletes the block from the DB
	local ok = send_del(DB_URL, block_id, BLOCK_CONSIST)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, send_del was not OK")
		return nil
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function del_iblock: deletes an iblock from the DB
local function del_iblock(iblock_n)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "del_iblock"
	--TODO: WEIRD LATENCY IN del_LOCAL, I THINK THE iblock DOES NOT GET DELETED.
	--logs START of the function
	--logprint(log_domain, function_name..": START. iblock_n="..iblock_n)
	--reads the iblock from the DB
	local iblock = get_iblock(iblock_n)
 	--for all the blocks refered by the iblock
	for i,v in ipairs(iblock.content) do
		--deletes the blocks. TODO: NOT CHECKING IF SUCCESSFUL
		del_block(v)
	end
	--deletes the iblock from the DB
	local ok = send_del(DB_URL, hash_string("iblock:"..iblock_n), IBLOCK_CONSIST)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, send_del was not OK")
		return nil
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function del_dblock: deletes a directory iblock from the DB
local function del_dblock(iblock_n)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "del_dblock"
	--checks input errors
	--if iblock_n is not a number
	if type(iblock_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, iblock_n not a number")
		return nil
	end
	--logs START of the function
	--logprint(log_domain, function_name..": START. iblock_n=", iblock_n)
	--deletes the iblock from the DB
	local ok = send_del(DB_URL, hash_string("iblock:"..iblock_n), DBLOCK_CONSIST)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--logprint(log_domain, function_name..": ERROR, send_del was not OK")
		return nil
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function del_file: deletes a file from the DB
local function del_file(filename)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "del_file"
	--if filename is not a string or it is an empty string
	if type(filename) ~= "string" or filename == "" then
		--reports the error, flushes all logs and returns nil
		--logprint(log_domain, function_name..": ERROR, filename not a string")
		return nil
	end
	--logs START of the function
	--logprint(log_domain, function_name..": START. filename=", filename)
	--deletes the file from the DB
	local ok = send_del(DB_URL, hash_string("file:"..filename), IBLOCK_CONSIST)
	--if the deletion was not successful
	if not ok then
		--reports the error, flushes all logs and returns nil
		--last_logprint(log_domain, function_name..": ERROR, send_del was not OK")
		return nil
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function gc_block: sends a block to the Garbage Collector
local function gc_block(block_id)
end


--COMMON ROUTINES FOR FUSE OPERATIONS

--function cmn_getattr: gets the attributes of a file
local function cmn_getattr(iblock)
	--for logprint calls
	local log_domain, function_name = "FILE_IBLOCK_OP", "cmn_getattr"
	--logs START-END of the function
	last_logprint(log_domain, function_name..": START.END.")
	--returns 0 (successful), mode, iblock number, device, number of links, userID, groupID, size, access time, modif time, iblock change time
	return 0, iblock.meta.mode, iblock.meta.ino, iblock.meta.dev, iblock.meta.nlink, iblock.meta.uid, iblock.meta.gid, iblock.meta.size, iblock.meta.atime, iblock.meta.mtime, iblock.meta.ctime
end

--function cmn_mk_file: creates a file in the FS
local function cmn_mk_file(filename, iblock_n, flags, mode, nlink, size, dev, content)
	--for logprint calls
	local log_domain, function_name = "FILE_MISC_OP", "cmn_mk_file"
	--logs START of the function
	logprint(log_domain, function_name..": START.")
	--initializes iblock
	local iblock = nil
	--if the function must check first if the iblock exists already
	if flags.CHECK_EXIST then
		--tries to get the iblock first
		iblock = get_iblock_from_filename(filename)
		--if the iblock exists, returns with error EEXIST
		if iblock then
			return EEXIST
		end
	end
	--splits the filename
	local dir, base = split_filename(filename)
	--gets the parent dblock
	local parent = get_dblock_from_filename(dir)
	--if the parent dblock does not exist, logs error and returns with error ENOENT
	if not parent then
		last_logprint(log_domain, function_name..": END. the parent dir does not exist, returning ENOENT")
		return ENOENT
	end
	--if the iblock_n is not given (the iblock does not exist), creates it
	if not iblock_n then
		--gets the iblock number
		iblock_n = generate_iblock_n()
		--takes userID, groupID, and processID from FUSE context
		local uid, gid, pid = fuse.context()
		--creates an empty iblock (or dblock)
		iblock = {
			meta = {
				ino = iblock_n,
				uid = uid,
				gid = gid,
				mode = mode,
				nlink = nlink or 1,
				size = size or 0,
				atime = os.time(),
				mtime = os.time(),
				ctime = os.time(),
				dev = dev or 0,
				xattr = {}
			},
			content = content or {}
		}
		--puts the iblock, because it's new
		put_iblock(iblock_n, iblock)
	end
	--puts the file, because it's new
	put_file(filename, iblock_n)
	--adds the entry into the parent dblock's contents table
	parent.content[base]=true
	--if the entry is a dir
	if flags.IS_DIR then
		--adds one link to the parent (the ".." link)
		parent.meta.nlink = parent.meta.nlink + 1
	end
	--if the flag UPDATE_PARENT is set
	if flags.UPDATE_PARENT then
		--updates the parent dblock, because the contents changed
		put_dblock(parent.meta.ino, parent)
		--clears parent so it does not get returned
		parent = nil
	end
	--logs END of the function
	last_logprint(log_domain, function_name..": END.")
	--returns 0
	return 0, iblock, parent
end

--function cmn_rm_file: removes a file from the FS
local function cmn_rm_file(filename, flags)
	--for logprint calls
	local log_domain, function_name = "FILE_MISC_OP", "cmn_rm_file"
	--logs START of the function
	logprint(log_domain, function_name..": START.")
	--gets the iblock
	local iblock = get_iblock_from_filename(filename)
	--if there is no iblock, returns the error code ENOENT (No such file or directory)
	if not iblock then
		return ENOENT
	end
	--logs
	--logprint(log_domain, function_name..": got iblock=", tbl2str("iblock", 0, iblock))
	--if it is a dir
	if flags.IS_DIR then
		--if there is at least one entry in iblock.content, returns error ENOTEMPTY
		for i,v in pairs(iblock.content) do
			--last_logprint(log_domain, function_name..": dir entry=", i)
			return ENOTEMPTY
		end
	end
	--splits the filename
	local dir, base = split_filename(filename)
	--gets the parent dblock
	local parent = get_dblock_from_filename(dir)
	--deletes the entry from the contents of the parent dblock
	parent.content[base] = nil
	--if it is a dir
	if flags.IS_DIR then
		--decrements the number of links in the parent dblock (one less dir pointing to it with the ".." element)
		parent.meta.nlink = parent.meta.nlink - 1
		--removes the iblock from the DB
		del_iblock(iblock.meta.ino)
	else
		--decrements the number of links
		iblock.meta.nlink = iblock.meta.nlink - 1
		--logs
		--logprint(log_domain, function_name..": now iblock has less links, =", tbl2str("iblock", 0, iblock))
		--if the iblock does not have any more links
		if iblock.meta.nlink == 0 then
			--logprint(log_domain, function_name..": iblock has to be deleted too")
			--deletes the iblock, since it's not linked anymore
			del_iblock(iblock.meta.ino)
		--if not, updates the iblock
		else
			put_iblock(iblock.meta.ino, iblock)
		end
	end
	--eitherway removes the file from the DB
	del_file(filename)
	--if the flag UPDATE_PARENT is set
	if flags.UPDATE_PARENT then
		--updates the parent dblock
		put_dblock(parent.meta.ino, parent)
		--clears parent so it does not get returned
		parent = nil
	end
	--logs END of function
	last_logprint(log_domain, function_name..": END.")
	--returns 0 and the parent dblock
	return 0, parent
end

--function cmn_read: common routine for reading from a file
local function cmn_read(size, offset, iblock)
	--for logprint calls
	local log_domain, function_name = "READ_WRITE_OP", "cmn_read"
	--logs START of the function
	logprint(log_domain, function_name..": START.")
	--calculates the starting block ID
	local start_block_idx = math.floor(offset / block_size)+1
	--calculates the offset on the starting block
	local rem_start_offset = offset % block_size
	--calculates the end block ID
	local end_block_idx = math.floor((offset+size-1) / block_size)+1
	--calculates the offset on the end block
	local rem_end_offset = (offset+size-1) % block_size
	--logs
	logprint(log_domain, function_name..": offset="..offset..", size="..size..", start_block_idx="..start_block_idx)
	logprint(log_domain, function_name..": rem_start_offset="..rem_start_offset..", end_block_idx="..end_block_idx..", rem_end_offset="..rem_end_offset)
	logprint(log_domain, function_name..": about to get block, block_n="..tostring(iblock.content[start_block_idx]))
	--logs
	logprint(log_domain, function_name..": orig_size et al. calculated, size="..size)
	--gets the first block; if the result of the get OP is empty, fills it out with an empty string
	local block = get_block(iblock.content[start_block_idx]) or ""
	--table that contains the data, then it gets concatenated (just a final concatenation shows better performance than concatenating inside the loop)
	local data_t = {}
	--logs (w/elapsed_time)
	--logprint(log_domain, function_name..": first block retrieved. elapsed_time="..(misc.time()-start_time))
	--if the starting block and the end block are the same, it does nothing but logging (the first block was retrieved above)
	if start_block_idx == end_block_idx then
		--logs
		--logprint(log_domain, function_name..": just one block to read")
		--logs (w/elapsed_time)
		table.insert(data_t, string.sub(block, rem_start_offset+1, rem_end_offset))
	--if not
	else
		--logs
		--logprint(log_domain, function_name..": several blocks to read")
		table.insert(data_t, string.sub(block, rem_start_offset+1))
		--for all blocks, from the second to the second last one
		for i=start_block_idx+1,end_block_idx-1 do
			--logs (w/elapsed_time)
			--logprint(log_domain, function_name..": getting new block. elapsed_time="..(misc.time()-start_time))
			--gets the block
			block = get_block(iblock.content[i]) or ""
			--inserts the block in data_t
			table.insert(data_t, block)
		end
		--logs (w/elapsed_time)
		--logprint(log_domain, function_name..": getting new block. elapsed_time="..(misc.time()-start_time))
		--gets last block
		block = get_block(iblock.content[end_block_idx]) or ""
		--inserts it only until the offset
		table.insert(data_t, string.sub(block, 1, rem_end_offset))
	end
	--logs END of the function (w/elapsed_time)
	--last_logprint(log_domain, function_name..": END. elapsed_time="..(misc.time()-start_time))
	--returns 0 and the concatenation of the data table
	return 0, table.concat(data_t)
end

--function cmn_write: common routine for writing in a file
local function cmn_write(buf, offset, iblock)
	--for logprint calls
	local log_domain, function_name = "READ_WRITE_OP", "cmn_write"
	--logs START of the function
	logprint(log_domain, function_name..": START.")
	--stores the size reported by the iblock in the variable orig_size
	local orig_size = iblock.meta.size
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
	logprint(log_domain, function_name..": orig_size="..orig_size..", offset="..offset..", size="..size..", start_block_idx="..start_block_idx)
	logprint(log_domain, function_name..": rem_start_offset="..rem_start_offset..", end_block_idx="..end_block_idx..", rem_end_offset="..rem_end_offset)
	--logs (w/elapsed_time)
	--logprint(log_domain, function_name..": orig_size et al. calculated, size="..size..". elapsed_time="..(misc.time()-start_time))
	--block, block_id and to_write_in_block are initialized to nil
	local block, block_id, to_write_in_block
	--initializes the block offset as the offset in the starting block
	local block_offset = rem_start_offset
	--calculates if the size of the file changed; if the offset+size is bigger than the original size, yes.
	local size_changed = ((offset + size) > orig_size)
	--initializes the remaining buffer as the whole buffer
	local remaining_buf = buf
	--logs
	logprint(log_domain, function_name..": calculated more stuff.")
	logprint(log_domain, function_name..": buf=\""..buf.."\"")
	--for all blocks from the starting to the end block
	for i = start_block_idx, end_block_idx do
		--logs
		logprint(log_domain, function_name..": im in the for loop, i="..i)
		--if the block exists
		if iblock.content[i] then
			--logs
			--logprint(log_domain, function_name..": block exists, so get the block")
			--gets the block; the block_id is the ith entry of iblock contents table
			block = get_block(iblock.content[i])
			--sends the block to GC
			gc_block(iblock.content[i])
		--if not
		else
			--logs
			--logprint(log_domain, function_name..": block doesnt exists, so create the block")
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
			--logprint(log_domain, function_name..": more than block size")
			--fills out to_write_in_block with enough data to reach the end of the block
			to_write_in_block = string.sub(remaining_buf, 1, (block_size - block_offset))
			--cuts that data from the remaining buffer
			remaining_buf = string.sub(remaining_buf, (block_size - block_offset)+1, -1)
		--if not (all the remaining buffer fits in the block)
		else
			--logs
			--logprint(log_domain, function_name..": less than block size")
			--to_write_in_block is equal to the remaining buffer
			to_write_in_block = remaining_buf
		end
		--logs
		logprint(log_domain, function_name..": block=\""..block.."\"")
		logprint(log_domain, function_name..": to_write_in_block=\""..to_write_in_block.."\"")
		--logprint(log_domain, function_name..": block_offset=", block_offset..", size of to_write_in_block=", #to_write_in_block)
		--inserts the to_write_in_block segment into the block. TODO: CHECK IF THE +1 AT THE END IS OK
		block = string.sub(block, 1, block_offset)..to_write_in_block..string.sub(block, (block_offset + #to_write_in_block + 1))
		--logs
		logprint(log_domain, function_name..": now block="..block)
		--the blockID is the hash of the iblock number concatenated with the block data
		block_id = hash_string(tostring(iblock.meta.ino)..block)
		--logs
		logprint(log_domain, function_name..": before putting the block, blockID=\""..block_id.."\"")
		--puts the block
		put_block(block_id, block)
		--logs
		logprint(log_domain, function_name..": after putting the block, before changing iblock, iblock.content["..i.."]="..tostring(iblock.content[i]))
		--inserts the new block number in the contents table
		iblock.content[i] = block_id
		--the block offset is set to 0
		--logs
		logprint(log_domain, function_name..": after changing the iblock, iblock.content["..i.."]="..tostring(iblock.content[i]))
		block_offset = 0
		--logs (w/elapsed_time)
		--logprint(log_domain, function_name..": end of a cycle. elapsed_time="..(misc.time()-start_time))
	end
	--if the size changed
	if size_changed then
		--changes the metadata in the iblock
		iblock.meta.size = offset+size
	end
	--logs END of the function
	--last_logprint(log_domain, function_name..": END.")
	return iblock
end

--function cmn_truncate: truncates a file to a given size, or appends zeros if the requested size is bigger than the original
local function cmn_truncate(iblock, size)
	--for logprint calls
	local log_domain, function_name = "READ_WRITE_OP", "cmn_truncate"
	--stores the size reported by the iblock in the variable orig_size
	local orig_size = iblock.meta.size
	--if the original size is less than the new size, append zeros
	if orig_size < size then
		local buf = string.rep("\0", size - orig_size)
		iblock = cmn_write(buf, orig_size, iblock)
		put_iblock(iblock.meta.ino, iblock)
		return 0
	end
	--calculates the index (in the iblock contents table) of the block where the pruning takes place
	local block_idx = math.floor((size - 1) / block_size) + 1
	--calculates the offset on the block
	local rem_offset = size % block_size
	--logs
	logprint(log_domain, function_name..": orig_size=", orig_size..", new_size=", size..", block_idx=", block_idx..", rem_offset=", rem_offset)
	--from the last block until the second last to be deleted (decremented for loop)
	for i=#iblock.content, block_idx+1,-1 do
		--logs
		logprint(log_domain, function_name..": about to remove block number iblock.content["..i.."]=", iblock.content[i])
		--sends the block to GC
		gc_block(iblock.content[i])
		--removes the block from the iblock contents
		table.remove(iblock.content, i)
	end
	--logs
	logprint(log_domain, function_name..": about to change block number iblock.content["..block_idx.."]=", iblock.content[block_idx])
	--if the remainding offset is 0
	if rem_offset == 0 then
		logprint(log_domain, function_name..": last block must be empty, so we delete it")
		--removes the block from the iblock contents
		table.remove(iblock.content, block_idx)
	--if not, we must truncate the block and rewrite it
	else
		--logs
		logprint(log_domain, function_name..": last block will not be empty")
		--gets the last block
		local last_block = get_block(iblock.content[block_idx])
		--logprint(log_domain, function_name..": it already has this=", last_block)
		local write_in_last_block = string.sub(last_block, 1, rem_offset)
		--logs
		logprint(log_domain, function_name..": and we change to this=", write_in_last_block)
		--the blockID is the hash of the iblock number concatenated with the block data
		local block_id = hash_string(tostring(iblock.meta.ino)..write_in_last_block)
		--puts the block
		put_block(block_id, write_in_last_block)
		--replaces with the new blockID the entry blockIdx in the contents table
		iblock.content[block_idx] = block_id
	end
	--eitherway, sends the block to GC
	gc_block(iblock.content[block_idx])
	iblock.meta.size = size
	--logs END of the function
	--last_logprint(log_domain, function_name..": END.")
	--returns the iblock
	return iblock
end


--START MAIN ROUTINE

--logs start
logprint("MAIN_OP", "MAIN: starting SPLAYFUSE")
--takes userID, groupID, etc., from FUSE context
local uid, gid, pid, puid, pgid = fuse.context()
--logs
--logprint("MAIN_OP", "MAIN: FUSE context taken. uid="..tostring(uid)..", gid="..tostring(gid)..", pid="..tostring(pid)..", puid="..tostring(puid)..", pgid="..tostring(pgid))
--the session register is identified with the hash of the string session_id
--NOTE: thinking of have a register for each user, but then, iblock number = uid + sessionID + seq_number, instead of only sessionID + seq_number
local session_reg_key = hash_string("session_id")
--logs
logprint("MAIN_OP", "MAIN: session_register=\""..session_reg_key.."\"")
--gets the session register from the DB
session_id = tonumber(send_get(DB_URL, session_reg_key, "paxos"))
--increments the sessionID. NOTE + TODO: the read + increment + write of the session register is not an atomic process
session_id = (1 + (session_id or 0)) % 10000
--logs
logprint("MAIN_OP", "MAIN: new sessionID="..session_id)
--puts the new sessionID into the DB
send_put(DB_URL, session_reg_key, "paxos", session_id)
--looks if the root_dblock is already in the DB
local root_dblock = get_dblock(1)
--logs
logprint("MAIN_OP", "MAIN: got root_dblock")
--if there isn't any
if not root_dblock then
	--logs
	logprint("FILE_IBLOCK_OP", "MAIN: creating root")
	--creates the root dblock
	root_dblock = {
		--metadata
		meta = {
			--iblock number is 1
			ino = 1,
			xattr ={},
			--mode is 755 + is a dir
			mode  = mk_mode(7,5,5) + S_IFDIR,
			--number of links = 2
			nlink = 2,
			uid = puid,
			gid = pgid,
			size = 0,
			atime = os.time(),
			mtime = os.time(),
			ctime = os.time()
		},
		--content is empty
		content = {}
	}
	--logs
	--logprint("FILE_IBLOCK_OP", "MAIN: going to put the root file")
	--puts root file
	put_file("/", 1)
	--logs
	--logprint("FILE_IBLOCK_OP", "MAIN: going to put the root dblock")
	--puts root iblock
	put_dblock(1, root_dblock)
end

--the splayfuse object, with all the FUSE methods
local splayfuse = {

	--function pulse: used in Lua memFS for "pinging"
	pulse = function()
		--logs START of the function
		--last_logprint("FILE_MISC_OP", "pulse: START.")
	end,

	--function getattr: gets the attributes of a requested file
	getattr = function(self, filename)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "getattr"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--gets the iblock from the DB
		local iblock = get_iblock_from_filename(filename)
		--if there is no iblock
		if not iblock then
			--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
			--last_logprint(log_domain, function_name..": END. no iblock found, returning ENOENT")
			return ENOENT
		end
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns the attributes of a file
		return cmn_getattr(iblock)
	end,

	--function fgetattr: gets the attributes of a requested file
	fgetattr = function(self, filename, iblock, ...)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "fgetattr"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--gets the iblock from the DB
		local iblock = get_iblock_from_filename(filename)
		--if there is no iblock
		if not iblock then
			--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
			--last_logprint(log_domain, function_name..": END. no iblock found, returning ENOENT")
			return ENOENT
		end
		--logs
		--logprint(log_domain, tbl2str("iblock", 0, iblock))
		--logs END of the function
		--last_logprint(log_domain, function_name..": END.")
		--returns the attributes of a file
		return cmn_getattr(iblock)
	end,

	--function mkdir: creates a directory
	mkdir = function(self, filename, mode, ...)
		--for logprint calls
		local log_domain, function_name = "DIR_OP", "mkdir"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--flags:
		local flags = {
			CHECK_EXIST=true,
			IS_DIR=true,
			UPDATE_PARENT=true
		}
		--the mode is mixed wit the flag S_IFDIR
		mode = set_bits(mode, S_IFDIR)
		--makes file; iblock=nil (creates iblock), number_links=2. TODO: CHECK IF SIZE IS NOT block_size
		local ok = cmn_mk_file(filename, nil, flags, mode, 2)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns the result of the operation
		return ok
	end,

	--function opendir: opens a directory
	opendir = function(self, filename)
		--for logprint calls
		local log_domain, function_name = "DIR_OP", "opendir"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename =", filename)
		--gets the dblock from the DB
		local dblock = get_dblock_from_filename(filename)
		--if there is no dblock, returns the error code ENOENT (No such file or directory)
		if not dblock then
			--last_logprint(log_domain, function_name..": END. no dblock found, returns ENOENT")
			return ENOENT
		end
		--logs
		--logprint(log_domain, function_name..": for filename =", filename, "get_dblock_from_filename returned=")
		--logprint(log_domain, tbl2str("dblock", 0, dblock))
		--logs END of the function
		--last_logprint(log_domain, function_name..": END.")
		--returns 0, and the dblock
		return 0, dblock
	end,

	readdir = function(self, filename, offset, dblock)
		--for logprint calls
		local log_domain, function_name = "DIR_OP", "readdir"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename="..filename..", offset="..offset)
		--looks for the dblock
		local dblock = get_dblock_from_filename(filename)
		--if there is no dblock, returns the error code ENOENT (No such file or directory). TODO: ENOENT is not valid for readdir
		if not dblock then
			--last_logprint(log_domain, function_name..": END. no dblock found, returns ENOENT")
			return ENOENT
		end
		--logs
		--logprint(log_domain, function_name..": dblock retrieved =")
		--logprint(log_domain, tbl2str("dblock", 0, dblock))
		--starts the file list with "." and ".."
		local out={'.','..'}
		--for each entry in content, adds it in the file list
		for k,v in pairs(dblock.content) do
			table.insert(out, k)
		end
		--returns 0 and the list of files
		return 0, out
	end,

	--function releasedir: closes a directory
	releasedir = function(self, filename, dblock)
		--logs START of the function
		logprint("DIR_OP", "releasedir: START. filename=", filename)
		--prints the dblock and flushes all logs
		--last_logprint("DIR_OP", tbl2str("dblock", 0, dblock))
		--returns 0
		return 0
	end,

	--function rmdir: removes a directory from the FS
	rmdir = function(self, filename)
		--for logprint calls
		local log_domain, function_name = "DIR_OP", "rmdir"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--flags:
		local flags = {
			IS_DIR = true,
			UPDATE_PARENT = true
		}
		--removes the file from the FS
		local ok = cmn_rm_file(filename, flags)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns the result of the operation
		return ok

	end,

	--function mknod: creates a new regular, special or fifo file
	mknod = function(self, filename, mode, rdev)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "mknod"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--flags:
		local flags = {
			CHECK_EXIST=true,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--makes file; iblock=nil (creates iblock), number_links=1, size=0, dev=rdev
		local ok = cmn_mk_file(filename, nil, flags, mode, 1, 0, rdev)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns the result of the operation
		return ok
	end,

	--function read: reads data from an open file. TODO: CHANGE MDATE and ADATE WHEN READING/WRITING
	read = function(self, filename, size, offset, iblock)
		--for logprint calls
		local log_domain, function_name = "READ_WRITE_OP", "read"
		--logs START of the function (w/elapsed_time)
		local start_time = misc.time()
		logprint(log_domain, function_name..": START. elapsed_time=0")
		--logprint(log_domain, function_name..": filename=", filename..", size=", size..", offset=", offset)
		--gets iblock from DB
		iblock = get_iblock_from_filename(filename)
		--logs
		--logprint(log_domain, function_name..": iblock retrieved =")
		--logprint(log_domain, tbl2str("iblock", 0, iblock))
		--if there is no iblock, returns 1. TODO: see how to handle this error
		if not iblock then
			return 1
		end
		--logs (w/elapsed_time)
		--logprint(log_domain, function_name..": iblock retrieved. elapsed_time="..(misc.time()-start_time))
		return cmn_read(size, offset, iblock)
	end,

	--function write: writes data into a file. TODO: CHANGE MDATE and ADATE WHEN WRITING
	write = function(self, filename, buf, offset, iblock)
		--for logprint calls
		local log_domain, function_name = "READ_WRITE_OP", "write"
		--logs START of the function (w/elapsed_time)
		local start_time = misc.time()
		logprint(log_domain, function_name..": START. filename=", filename, "elapsed_time=0")
		--gets iblock from the DB
		local iblock = get_iblock_from_filename(filename)
		--TODO: falta si el iblock no existe
		--logs
		logprint(log_domain, function_name..": iblock retrieved=")
		--logprint(log_domain, tbl2str("iblock", 0, iblock))
		--logs (w/elapsed_time)
		--logprint(log_domain, function_name..": iblock retrieved. elapsed_time="..(misc.time()-start_time))
		--performs a FUSE write with Open-Close consistency
		iblock = cmn_write(buf, offset, iblock)
		--puts the iblock into the DB
		put_iblock(iblock.meta.ino, iblock)
		--logs
		--logprint(log_domain, function_name..": iblock was written. elapsed_time="..(misc.time()-start_time))
		--logs END of the function (w/elapsed_time)
		last_logprint(log_domain, function_name..": END. elapsed_time="..(misc.time()-start_time))
		--returns the size of the written buffer
		return #buf
	end,

	--function open: opens a file for read/write operations
	open = function(self, filename, mode)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "open"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--m is the remainder mode divided by 4
		local m = mode % 4
		--gets the iblock from the DB
		local iblock = get_iblock_from_filename(filename)
		--if there is no iblock, returns the error code ENOENT (No such file or directory)
		if not iblock then
			--last_logprint(log_domain, function_name..": END. no iblock found, returns ENOENT")
			return ENOENT
		end
		--[[
		--NOTE: CODE RELATED TO SESSION ORIENTED MODE
		if not iblock then return ENOENT end
		iblock.open = (iblock.open or 0) + 1
		put_iblock(iblock.meta.ino, iblock)
		--TODO: CONSIDER CHANGING A FIELD OF THE DISTDB WITHOUT RETRIEVING THE WHOLE OBJECT; DIFFERENTIAL WRITE
		--]]
		--returns 0 and the iblock
		return 0, iblock
	end,

	--function release: closes an open file
	--NOTE: RELEASE DOESNT MAKE SENSE WHEN USING ATOMIC READ WRITES
	release = function(self, filename, iblock)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "release"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)

		--[[
		--NOTE: CODE RELATED TO OPEN-CLOSE MODE
		iblock.open = iblock.open - 1
		if iblock.open < 1 then
			--logprint(log_domain, function_name..": open < 1")
			if iblock.changed then
				--logprint(log_domain, function_name..": going to put")
				local ok_put_iblock = put_iblock(iblock.ino, iblock)
			end
			if iblock.meta_changed then
				--logprint(log_domain, function_name..": going to put")
				local ok_put_iblock = put_iblock(iblock.ino, iblock)
			end
			--logprint(log_domain, function_name..": meta_changed = nil")
			iblock.meta_changed = nil
			--logprint(log_domain, function_name..": changed = nil")
			iblock.changed = nil
		end
		--]]
		--returns 0
		return 0
	end,

	--function create: creates and opens a file
	create = function(self, filename, mode, flags, ...)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "create"
		--logs START of the function
		logprint(log_domain, function_name..": START. type_flags=", type(flags), "filename=", filename)
		--flags:
		local flags = {
			CHECK_EXIST=false,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--the file is regular (S_IFREG set)
		mode = set_bits(mode, S_IFREG)
		--makes file; iblock=nil (creates iblock)
		local ok = cmn_mk_file(filename, nil, flags, mode)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns the result of the operation
		return ok
	end,

	--function flush: cleans local record about an open file
	flush = function(self, filename, iblock)
		--logs START of the function
		logprint("FILE_MISC_OP", "flush: START. filename=", filename)
		--if the iblock changed
		if iblock.changed then
			--TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
		end
		--returns 0
		return 0
	end,

	--function readlink: reads a symbolic link
	readlink = function(self, filename)
		--logs START of the function
		logprint("LINK_OP", "readlink: START. filename=", filename)
		--gets iblock from the DB
		local iblock = get_iblock_from_filename(filename)
		--if there is not an iblock
		if not iblock then
			--logs END of the function
			last_logprint(log_domain, function_name..": END. no iblock, returns ENOENT")
			--returns ENOENT
			return ENOENT
		end
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns 0 and the symbolic link
		return 0, iblock.content[1]
	end,

	--function symlink: makes a symbolic link.
	symlink = function(self, from, to)
		--for logprint calls
		local log_domain, function_name = "LINK_OP", "symlink"
		--logs START of the function
		logprint(log_domain, function_name..": START. from=", from, "to=", to)
		--flags:
		local flags = {
			CHECK_EXIST=true,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--the mode for symbolic link is 777 with the flag S_IFLNK set
		local mode = S_IFLNK + mk_mode(7,7,7)
		--makes file; iblock=nil (creates iblock), number_links=1, size=0, dev=rdev, content is the string "from"
		local ok = cmn_mk_file(to, nil, mode, 1, string.len(from), 0, {from})
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns the result of the operation
		return ok
	end,

	--function rename: moves/renames a file
	rename = function(self, from, to)
		--for logprint calls
		local log_domain, function_name = "MV_CP_OP", "rename"
		--logs START of the function
		logprint(log_domain, function_name..": START. from=", from..", to=", to)
		--if the "from" file is equal to the "to" file. TODO: the man page says it should do that, but BASH's "mv" sends an error
		if from == to then return 0 end
		--gets the "from" iblock
		local from_iblock = get_iblock_from_filename(from)
		--if there is not a "from" iblock, returns ENOENT
		if not from_iblock then
			return ENOENT
		end
		--splits the "from" filename
		local from_dir, from_base = split_filename(from)
		--splits the "to" filename
		local to_dir, to_base = split_filename(to)
		--gets the parent dblock of the "from" file
		local from_parent = get_iblock_from_filename(from_dir)
		--initializes the parent dblock of the "to" file as nil
		local to_parent = nil
		--if the "to" and "from" parent dblocks are the same
		if to_dir == from_dir then
			--to_parent is the from_parent (no need to look it up again)
			to_parent = from_parent
		--if not
		else
			--gets the "to" parent dblock
			to_parent = get_iblock_from_filename(to_dir)
		end
		--adds the entry into the "to" parent dblock
		to_parent.content[to_base] = true
		--deletes the entry from the "from" parent dblock
		from_parent.content[from_base] = nil
		--logs
		--logprint(log_domain, function_name..": changes made", {to_parent=to_parent, from_parent=from_parent})
		--only if "to" and "from" are different (avoids writing on parent's dblock twice, for the sake of efficiency)
		if to_dir ~= from_dir then
			--updates the to_parent dblock, because the contents changed
			put_iblock(to_parent.meta.ino, to_parent)
		end
		--updates the from_parent's dblock, because the contents changed
		put_iblock(from_parent.meta.ino, from_parent)
		--puts the "to" file, because it's new
		put_file(to, from_iblock.meta.ino)
		--deletes the "from" file
		del_file(from)
		--returns 0
		return 0
	end,

	--function link: makes a hard link. TODO: not permitted for dir EPERM
	link = function(self, from, to, ...)
		--for logprint calls
		local log_domain, function_name = "LINK_OP", "link"
		--logs START of the function
		logprint(log_domain, function_name..": START. from=", from..", to=", to)
		--if "from" and "to" are the same, do nothing; return 0
		if from == to then return 0 end
		--gets the "from" iblock
		local from_iblock = get_iblock_from_filename(from)
		--if there is not a "from" iblock, returns ENOENT
		if not from_iblock then
			return ENOENT
		end
		--logs
		--logprint(log_domain, function_name..": entered in IF")
		--splits the "to" filename
		local to_dir, to_base = split_filename(to)
		--logs
		--logprint(log_domain, function_name..": to_dir=", to_dir..", to_base=", to_base)
		--gets the parent dblock of the "to" file
		local to_parent = get_iblock_from_filename(to_dir)
		--logs
		--logprint(log_domain, function_name..": to_parent", {to_parent=to_parent})
		--adds an entry to the "to" parent dblock
		to_parent.content[to_base] = true
		--logs
		--logprint(log_domain, function_name..": added file in to_parent", {to_parent=to_parent})
		--increments the number of links in the iblock
		from_iblock.meta.nlink = from_iblock.meta.nlink + 1
		--updates the to_parent dblock, because the contents changed
		put_iblock(to_parent.meta.ino, to_parent)
		--puts the iblock, because nlink was incremented
		put_iblock(from_iblock.meta.ino, from_iblock)
		--puts the "to" file, because it's new
		put_file(to, from_iblock.meta.ino)
		--returns 0
		return 0
	end,

	--function unlink: deletes a link to an iblock
	unlink = function(self, filename, ...)
		--for logprint calls
		local log_domain, function_name = "LINK_OP", "unlink"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)
		--flags:
		local flags = {
			IS_DIR = false,
			UPDATE_PARENT = true
		}
		--removes the file from the FS
		local ok = cmn_rm_file(filename, flags)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns result
		return 0
	end,

	--function chown: changes the owner and/or the group of a file
	chown = function(self, filename, uid, gid)
		--logs START of the function
		logprint("FILE_MISC_OP", "chown: START. filename=\""..filename.."\", uid="..tostring(uid)..", gid="..tostring(gid))
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		--changes the uid and gid
		iblock.meta.uid = uid
		iblock.meta.gid = gid
		--updates the iblock on the DB
		put_iblock(iblock.meta.ino, iblock)
		--logs END of the function
		last_logprint("FILE_MISC_OP", "chown: END.")
		--returns 0
		return 0
	end,

	--function chmod: changes the mode of a file
	chmod = function(self, filename, mode)
		--logs START of the function
		logprint("FILE_MISC_OP", "chmod: START. filename=\""..filename.."\", mode="..mode)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		--changes the mode
		iblock.meta.mode = mode
		--updates the iblock on the DB
		put_iblock(iblock.meta.ino, iblock)
		--logs END of the function
		last_logprint("FILE_MISC_OP", "chmod: END.")
		--returns 0
		return 0
	end,

	utime = function(self, filename, atime, mtime)
		--logs START of the function
		logprint("FILE_MISC_OP", "utime: START. filename="..filename.."atime="..atime.."mtime="..mtime)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		--changes the times
		iblock.meta.atime = atime
		iblock.meta.mtime = mtime
		--updates the iblock on the DB
		put_iblock(iblock.meta.ino, iblock)
		--logs END of the function
		last_logprint("FILE_MISC_OP", "utime: END.")
		--returns 0
		return 0
	end,

	--function ftruncate: truncates a file using directly the iblock as reference.
	ftruncate = function(self, filename, size, iblock)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "ftruncate"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename, "size=", size)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--logs
		--logprint(log_domain, function_name..": iblock was retrieved=")
		--logprint(log_domain, tbl2str("iblock", 0, iblock))
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		--truncates the file
		iblock = cmn_truncate(iblock, size)
		--logprint(log_domain, function_name..": about to write iblock")
		put_iblock(iblock.meta.ino, iblock)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns 0
		return 0
	end,

	truncate = function(self, filename, size)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "truncate"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename, "size=", size)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--logs
		--logprint(log_domain, function_name..": iblock was retrieved=")
		--logprint(log_domain, tbl2str("iblock", 0, iblock))
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		--truncates the file
		iblock = cmn_truncate(iblock, size)
		--logprint(log_domain, function_name..": about to write iblock")
		put_iblock(iblock.meta.ino, iblock)
		--logs END of the function
		last_logprint(log_domain, function_name..": END.")
		--returns 0
		return 0
	end,

	access = function(...)
		--logs START of the function
		logprint("FILE_MISC_OP", "access: START.END.")
		
		return 0
	end,

	fsync = function(self, filename, isdatasync, iblock)
		--logs START of the function
		logprint("FILE_MISC_OP", "fsync: START. filename=", filename)
		--TODO: PA DESPUES
		--[[
		mnode.flush_node(iblock, filename, false) 
		if isdatasync and iblock.changed then 
			mnode.flush_data(iblock.content, iblock, filename) 
		end
		--]]
		return 0
	end,

	fsyncdir = function(self, filename, isdatasync, iblock)
		--logs START of the function
		logprint("FILE_MISC_OP", "fsyncdir: START. filename=", filename)
		--returns 0
		return 0
	end,

	listxattr = function(self, filename, size)
		--logs START of the function
		logprint("FILE_MISC_OP", "listxattr: START. filename=", filename)

		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		local v={}
		for k in pairs(iblock.meta.xattr) do 
			if type(k) == "string" then v[#v+1]=k end
		end
		return 0, table.concat(v,"\0") .. "\0"
	end,

	removexattr = function(self, filename, name)
		--logs START of the function
		logprint("FILE_MISC_OP", "removexattr: START. filename=", filename)

		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		iblock.meta.xattr[name] = nil
		put_iblock(iblock.meta.ino, iblock)
		return 0
	end,

	setxattr = function(self, filename, name, val, flags)
		--logs START of the function
		logprint("FILE_MISC_OP", "setxattr: START. filename=", filename)

		--string.hex = function(s) return s:gsub(".", function(c) return format("%02x", string.byte(c)) end) end
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		iblock.meta.xattr[name]=val
		put_iblock(iblock.meta.ino, iblock)
		return 0
	end,

	getxattr = function(self, filename, name, size)
		--for logprint calls
		local log_domain, function_name = "FILE_MISC_OP", "getxattr"
		--logs START of the function
		logprint(log_domain, function_name..": START. filename=", filename)

		local iblock = get_iblock_from_filename(filename)
		--logprint(log_domain, function_name..": get_iblock was successful =")
		--logprint(log_domain, tbl2str("iblock", 0, iblock))
		--if the iblock does not exist, returns ENOENT
		if not iblock then
			return ENOENT
		end
		--returns 0 and the attribute (if not found, returns empty string)
		return 0, iblock.meta.xattr[name] or ""
	end,

	statfs = function(self, filename)
		--TODO: improve this data
		local o = {
			bs = block_size,
			blocks=64,
			bfree=48,
			bavail=48,
			bfiles=16,
			bffree=16
		}
		return 0, o.bs, o.blocks, o.bfree, o.bavail, o.bfiles, o.bffree
	end
}

--logs
logprint("MAIN_OP", "MAIN: before defining fuse_opt")
--fills the fuse options out
fuse_opt = {'splayfuse', 'mnt', '-f', '-s', '-d', '-oallow_other'}
--logs
logprint("MAIN_OP", "MAIN: fuse_opt defined")
--if the amount of argumenst is less than two
if select('#', ...) < 2 then
	--prints usage
	print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
	--exits
	os.exit(1)
end
--logs
logprint("MAIN_OP", "MAIN: going to execute fuse.main")
--starts FUSE
fuse.main(splayfuse, {...})