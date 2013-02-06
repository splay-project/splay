#!/usr/bin/env lua
--[[
	FlexiFS: Distributed FS in FUSE using the LUA bindings
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
local dbclient = require"distdb-client-async"
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
--ENOENT = "No such file or directory"
local ENOENT = -2
--EACCES = "Permission denied"
local EACCES = -13
--ENOSYS = "Function not implemented"
local ENOSYS = -38
--ENOTEMPTY = "Directory not empty"
local ENOTEMPTY = -39

--consistency types can be "evtl_consistent", "paxos" or "consistent"
local IBLOCK_CONSIST = "consistent"
local DBLOCK_CONSIST = IBLOCK_CONSIST
local BLOCK_CONSIST = "consistent"
--the URL of the Entry Point to the distDB
local DB_URL = "127.0.0.1:15091"


--LOCAL VARIABLES

local block_size = 48
local blank_block = string.rep("\0", block_size)
--TODO: what is this for? check in memfs
local open_mode = {'rb','wb','rb+'}
local session_id = nil
local seq_number = 0

--VARIABLES FOR LOGGING

--the path to the log file is stored in the variable logfile; to log directly on screen, logfile must be set to "<print>"
local logfile = os.getenv("HOME").."/Desktop/logfusesplay/log.txt"
--to allow all logs, there must be the rule "allow *"
local logrules = {
	"deny DIST_DB_CLIENT",
	"deny RAW_DATA",
	"deny MEGA_DEBUG",
	"allow FUSE_API",
	"allow TEST_TAG"
}
--[["deny FS2DB_OP",
	"allow *",
	"allow MAIN",
	"allow FILE_IBLOCK_OP",
	"allow DIR_OP",
	"allow LINK_OP",
	"allow READ_WRITE_OP",
	"allow FILE_MISC_OP",
	"allow MV_CP_OP"]]
--if logbatching is set to true, log printing is performed only when explicitely running logflush()
local logbatching = false
local global_details = false
local global_timestamp = false
local global_elapsed = false

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
	--starts the logger
	local log1 = start_logger(".FILE_IBLOCK_OP decode_acl", "INPUT", "acl="..acl)
	local version = acl:sub(1,4)
	local n = 5
	while true do
		local tag = acl:sub(n, n + 1)
		local perm = acl:sub(n + 2, n + 3)
		local id = acl:sub(n + 4, n + 7)
		n = n + 8
		if n >= #acl then break end
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
end

--function mk_mode: creates the mode from the owner, group, world rights and the sticky bit
local function mk_mode(owner, group, world, sticky)
	--starts the logger
	local log1 = start_logger(".FILE_IBLOCK_OP mk_mode", "INPUT", "owner="..tostring(owner)..", group="..tostring(group)..", world="..tostring(world)..", sticky="..tostring(sticky))
	--result mode is the combination of the owner, group, world rights and the sticky mode
	local result_mode = owner * S_UID + group * S_GID + world + ((sticky or 0) * S_SID)
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "", "result_mode="..result_mode)
	--returns the mode
	return result_mode
end

--function hash_string: performs SHA1 of a string
local function hash_string(str)
	return crypto.evp.digest("sha1", str)
end

--function generate_iblock_n: generates an iblock number using the sessionID and sequence number
local function generate_iblock_n()
	--starts the logger
	local log1 = start_logger(".FILE_IBLOCK_OP generate_iblock_n", "INPUT", "session_id="..session_id)
	--increments the seq number
	seq_number = (seq_number + 1) % 1000
	--the iblock number is 1000 times the session id + sequence number
	local iblock_n = (1000 * session_id) + seq_number
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "", "seq number="..seq_number.."iblock_n="..iblock_n)
	--returns the iblock number
	return iblock_n
end


--FS TO DB FUNCTIONS

--GET FUNCTIONS

--function get_block: gets a block from the DB
local function get_block(block_id)
	--starts the logger
	local log1 = start_logger(".FS2DB_OP get_block", "INPUT", "block_id="..tostring(block_id))
	--if the blockID is nil, returns nil
	if not block_id then
		log1:logprint_flush("END", "blockID is nil")
		return nil
	end
	--reads the file from the DB
	local ok, block = send_get(DB_URL, block_id, BLOCK_CONSIST)
	--if the reading was not successful (ERROR), returns nil
	if not ok then
		log1:logprint("ERROR END", "send_get was not OK")
		return nil
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "", "block=\""..tostring(block).."\"")
	--returns the block data
	return block
end

--function get_iblock: gets an iblock from the DB
local function get_iblock(iblock_n)
	--starts the logger
	local log1 = start_logger(".FS2DB_OP get_iblock", "INPUT", "iblock_n="..tostring(iblock_n), true)
	--if the iblock is nil, returns nil
	if not iblock_n then
		log1:logprint_flush("END", "block_n is nil")
		return nil
	end
	--reads the iblock from the DB
	local ok, iblock_serial = send_get(DB_URL, hash_string("iblock:"..iblock_n), IBLOCK_CONSIST)
	--logs
	log1:logprint(".RAW_DATA", "serialized iblock retrieved", "ok="..tostring(ok)..", iblock_serial=\""..tostring(iblock_serial).."\"")
	--if the reading was not successful (ERROR), returns nil
	if not ok then
		log1:logprint("ERROR END", "send_get was not OK")
		return nil
	end
	--if the requested record is empty, returns nil
	if not iblock_serial then
		log1:logprint_flush("END", "iblock_serial is nil, returning nil")
		return nil
	end
	--deserializes the iblock
	local iblock = serializer.decode(iblock_serial)
	--prints the iblock
	log1:logprint(".TABLE", "iblock retrieved", tbl2str("iblock", 0, iblock))
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns the iblock
	return iblock
end

--get_dblock does the same as get_iblock
local get_dblock = get_iblock

--function get_iblock_n: gets an iblock number from the DB, by identifying it with the filename
local function get_iblock_n(filename)
	--starts the logger
	local log1 = start_logger(".FS2DB_OP get_iblock_n", "INPUT", "filename="..filename, true)
	--reads the file from the DB
	local ok, iblock_n = send_get(DB_URL, hash_string("file:"..filename), IBLOCK_CONSIST)
	--if the reading was not successful (ERROR), returns nil
	if not ok then
		log1:logprint("ERROR END", "send_get was not OK")
		return nil
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "", "iblock_n="..tostring(iblock_n))
	--returns the iblock number
	return tonumber(iblock_n)
end

--get_dblock_n does the same as get_iblock_n
local get_dblock_n = get_iblock_n

--function get_iblock_from_filename: gets an iblock from the DB, by identifying it with the filename
local function get_iblock_from_filename(filename)
	--starts the logger
	local log1 = start_logger(".FS2DB_OP get_iblock_from_filename", "INPUT", "filename="..filename, true)
	--the iblock number is extracted by calling get_iblock_n
	local iblock_n = get_iblock_n(filename)
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "", "iblock_n="..tostring(iblock_n))
	--returns the corresponding iblock
	return get_iblock(iblock_n)
end

--function get_dblock_from_filename does the sames as get_iblock_from_filename
local get_dblock_from_filename = get_iblock_from_filename

--PUT FUNCTIONS

--function put_block: puts a block into the DB
local function put_block(block_id, block)
	--starts the logger
	local log1 = start_logger(".FS2DB_OP put_block", "INPUT", "block_id="..block_id..", block_size="..string.len(block))
	--writes the block in the DB
	local ok = async_send_put(DB_URL, block_id, BLOCK_CONSIST, block)
	--if the writing was not successful (ERROR), returns nil
	if not ok then
		log1:logprint_flush("ERROR END", "", "send_put was not OK")
		return nil
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns true
	return true
end

--function put_iblock: puts an iblock into the DB
local function put_iblock(iblock_n, iblock)
	--starts the logger
	local log1 = start_logger(".FS2DB_OP put_iblock", "INPUT", "iblock_n="..iblock_n)
	--prints the iblock
	log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "calling send_put")
	--returns the result of send_put
	return send_put(DB_URL, hash_string("iblock:"..iblock_n), IBLOCK_CONSIST, serializer.encode(iblock))
end
--put_dblock does the same as put_iblock
local put_dblock = put_iblock

--function put_file: puts a file into the DB
local function put_file(filename, iblock_n)
	--starts and ends the logger
	local log1 = start_end_logger(".FS2DB_OP put_file", "calling send_put", "filename="..filename..", iblock_n="..iblock_n)
	--returns the result of send_put
	return send_put(DB_URL, hash_string("file:"..filename), IBLOCK_CONSIST, iblock_n)
end

--DELETE FUNCTIONS

--function del_block: deletes a block from the DB
local function del_block(block_id)
	--starts and ends the logger
	local log1 = start_end_logger(".FS2DB_OP del_block", "calling send_del", "block_n="..block_n)
	--returns the result of send_del
	return send_del(DB_URL, block_id, BLOCK_CONSIST)
end

--function del_iblock: deletes an iblock from the DB
local function del_iblock(iblock_n, is_dblock)
	--starts the logger. TODO: WEIRD LATENCY IN del_LOCAL, I THINK THE iblock DOES NOT GET DELETED.
	local log1 = start_logger(".FS2DB_OP del_iblock", "INPUT", "iblock_n="..iblock_n..", is_dblock="..tostring(is_dblock))
	--reads the iblock from the DB
	local iblock = get_iblock(iblock_n)
	--if the iblock is not a dblock, it has pointers to block that must be deleted too
	if not is_dblock then
 		--for all the blocks refered by the iblock
		for i,v in ipairs(iblock.content) do
			--logs
			log1:logprint_flush("", "about to delete block with ID="..v)
			--deletes the blocks. TODO: NOT CHECKING IF SUCCESSFUL
			del_block(v)
		end
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "calling send_del")
	--returns the result of send_del
	return send_del(DB_URL, hash_string("iblock:"..iblock_n), IBLOCK_CONSIST)
end

--function del_dblock: alias to del_iblock with flag is_dblock set to true
local function del_dblock(iblock_n)
	return del_iblock(iblock_n, true)
end

--function del_file: deletes a file from the DB
local function del_file(filename)
	--starts the logger
	local log1 = start_end_logger(".FS2DB_OP del_file", "calling send_del", "filename="..filename)
	--returns the result of send_del
	return send_del(DB_URL, hash_string("file:"..filename), IBLOCK_CONSIST)
end

--function gc_block: sends a block to the Garbage Collector
local function gc_block(block_id)
end


--COMMON ROUTINES FOR FUSE OPERATIONS

--function cmn_getattr: gets the attributes of an iblock
local function cmn_getattr(iblock)
	--starts the logger
	local log1 = start_logger(".COMMON_OP cmn_getattr")
	--prints the iblock
	log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns 0 (successful), mode, iblock number, device, number of links, userID, groupID, size, access time, modif time, iblock change time
	return 0, iblock.mode, iblock.ino, iblock.dev, iblock.nlink, iblock.uid, iblock.gid, iblock.size, iblock.atime, iblock.mtime, iblock.ctime
end

--function cmn_mk_file: creates a file in the FS; if iblock_n is specified, it does not creates a new iblock
local function cmn_mk_file(filename, iblock_n, flags, mode, nlink, size, dev, content)
	--starts the logger
	local log1 = start_logger(".COMMON_OP .FILE_MISC_OP cmn_mk_file", "INPUT", "filename="..filename..", iblock_n="..tostring(iblock_n), true)
	--initializes iblock
	local iblock = nil
	--if the function must check first if the iblock exists already
	if flags.CHECK_EXIST then
		--tries to get the iblock first
		iblock = get_iblock_from_filename(filename)
		--if the iblock exists (ERROR), returns EEXIST
		if iblock then
			log1:logprint_flush("ERROR END", "iblock already exists, returning EEXIST")
			return EEXIST
		end
	end
	--splits the filename
	local dir, base = split_filename(filename)
	--gets the parent dblock
	local parent = get_dblock_from_filename(dir)
	--if the parent dblock does not exist (ERROR), returns ENOENT
	if not parent then
		log1:logprint_flush("ERROR END", "", "the parent dblock does not exist, returning ENOENT")
		return ENOENT
	end
	--if the iblock_n is not given (the iblock does not exist), creates it
	if not iblock_n then
		--logs
		log1:logprint("", "iblock must be created")
		--gets the iblock number
		iblock_n = generate_iblock_n()
		--takes userID, groupID, and processID from FUSE context
		local uid, gid, pid = fuse.context()
		--creates an empty iblock (or dblock)
		iblock = {
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
			xattr = {},
			open_sessions = 0,
			content = content or {}
		}
		--prints the iblock
		log1:logprint(".TABLE", "iblock created", tbl2str("iblock", 0, iblock))
		--puts iblock in the DB, because it's new
		put_iblock(iblock_n, iblock)
	end
	--puts the file, because it's new
	put_file(filename, iblock_n)
	--adds the entry into the parent dblock's contents table
	parent.content[base]=true
	--if the entry is a dir
	if flags.IS_DIR then
		--adds one link to the parent (the ".." link)
		parent.nlink = parent.nlink + 1
	end
	--if the flag UPDATE_PARENT is set to true
	if flags.UPDATE_PARENT then
		--updates the parent dblock, because the contents changed
		put_dblock(parent.ino, parent)
		--clears parent so it does not get returned
		parent = nil
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns 0
	return 0, iblock, parent
end

--function cmn_rm_file: removes a file from the FS
local function cmn_rm_file(filename, flags)
	--starts the logger
	local log1 = start_logger(".COMMON_OP .FILE_MISC_OP cmn_rm_file", "INPUT", "filename="..filename)
	--gets iblock from DB
	local iblock = get_iblock_from_filename(filename)
	--if the iblock does not exist (ERROR), returns ENOENT
	if not iblock then
		log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
		return ENOENT
	end
	--prints the iblock
	log1:logprint(".TABLE", "iblock retrieved", tbl2str("iblock", 0, iblock))
	--if flag IS_DIR is set to true
	if flags.IS_DIR then
		--if there is at least one entry in iblock.content (ERROR), returns ENOTEMPTY
		for i,v in pairs(iblock.content) do
			log1:logprint_flush("ERROR END", "the dir is not empty", "dir entry="..i)
			return ENOTEMPTY
		end
	end
	--splits the filename
	local dir, base = split_filename(filename)
	--gets the parent dblock
	local parent = get_dblock_from_filename(dir)
	--deletes the entry from the contents of the parent dblock
	parent.content[base] = nil
	--if flag IS_DIR is set to true
	if flags.IS_DIR then
		--decrements the number of links in the parent dblock (one less dir pointing to it with the ".." element)
		parent.nlink = parent.nlink - 1
		--removes the iblock from the DB
		del_iblock(iblock.ino)
	--if not
	else
		--decrements the number of links
		iblock.nlink = iblock.nlink - 1
		--logs
		log1:logprint("", "now the iblock has less links", "nlink="..iblock.nlink)
		--if the iblock does not have any more links, deletes the iblock, since it's not linked anymore
		if iblock.nlink == 0 then
			log1:logprint("", "iblock has to be deleted too")
			del_iblock(iblock.ino)
		--if not, updates the iblock
		else
			put_iblock(iblock.ino, iblock)
		end
	end
	--eitherway removes the file from the DB
	del_file(filename)
	--if the flag UPDATE_PARENT is set to true
	if flags.UPDATE_PARENT then
		--updates the parent dblock
		put_dblock(parent.ino, parent)
		--clears parent so it does not get returned
		parent = nil
	end
	--logs END of function
	log1:logprint_flush("END")
	--returns 0 and the parent dblock
	return 0, parent
end

--function cmn_read: common routine for reading from a file
local function cmn_read(size, offset, iblock)
	--starts the logger
	local log1 = start_logger(".COMMON_OP .READ_WRITE_OP cmn_read", "INPUT", "size="..size..", offset="..offset)
	--prints the iblock
	log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
	--calculates the starting block ID
	local start_block_idx = math.floor(offset / block_size)+1
	--calculates the offset on the starting block
	local rem_start_offset = offset % block_size
	--calculates the end block ID
	local end_block_idx = math.floor((offset+size-1) / block_size)+1
	--calculates the offset on the end block
	local rem_end_offset = (offset+size-1) % block_size
	--logs
	log1:logprint("", "offset="..offset..", size="..size..", start_block_idx="..start_block_idx)
	log1:logprint("", "rem_start_offset="..rem_start_offset..", end_block_idx="..end_block_idx..", rem_end_offset="..rem_end_offset)
	log1:logprint("", "about to get block", "block_n="..tostring(iblock.content[start_block_idx]))
	--gets the first block; if the result of the get OP is empty, fills it out with an empty string
	local block = get_block(iblock.content[start_block_idx]) or ""
	--table that contains the data, then it gets concatenated (just a final concatenation shows better performance than concatenating inside the loop)
	local data_t = {}
	--logs
	log1:logprint(".RAW_DATA", "first block retrieved", "block=\""..block.."\"")
	--if the starting block and the end block are the same, it does nothing but logging (the first block was retrieved above)
	if start_block_idx == end_block_idx then
		--logs
		log1:logprint("", "just one block to read")
		--inserts the data from the block
		table.insert(data_t, string.sub(block, rem_start_offset+1, rem_end_offset))
	--if not
	else
		--logs
		log1:logprint("", "several blocks to read")
		table.insert(data_t, string.sub(block, rem_start_offset+1))
		--for all blocks, from the second to the second last one
		for i=start_block_idx+1,end_block_idx-1 do
			--logs
			log1:logprint("", "about to get a new block")
			--gets the block
			block = get_block(iblock.content[i]) or ""
			--inserts the block in data_t
			table.insert(data_t, block)
		end
		--logs
		log1:logprint("", "about to get a new block")
		--gets last block
		block = get_block(iblock.content[end_block_idx]) or ""
		--inserts it only until the offset
		table.insert(data_t, string.sub(block, 1, rem_end_offset))
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns 0 and the concatenation of the data table
	return 0, table.concat(data_t)
end

--function cmn_write: common routine for writing in a file
local function cmn_write(buf, offset, iblock)
	--starts the logger
	local log1 = start_logger(".COMMON_OP .READ_WRITE_OP cmn_write", "INPUT", "offset="..offset)
	--prints the buffer
	log1:logprint(".RAW_DATA", "INPUT", "buf=\""..buf.."\"")
	--prints the iblock
	log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
	--stores the size reported by the iblock in the variable orig_size
	local orig_size = iblock.size
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
	log1:logprint("", "offset="..offset..", size="..size..", start_block_idx="..start_block_idx)
	log1:logprint("", "rem_start_offset="..rem_start_offset..", end_block_idx="..end_block_idx..", rem_end_offset="..rem_end_offset)
	--block, block_id and to_write_in_block are initialized to nil
	local block, block_id, to_write_in_block
	--initializes the block offset as the offset in the starting block
	local block_offset = rem_start_offset
	--calculates if the size of the file changed; if the offset+size is bigger than the original size, yes.
	local size_changed = ((offset + size) > orig_size)
	--initializes the remaining buffer as the whole buffer
	local remaining_buf = buf
	--logs
	log1:logprint("", "more things calculated")
	--for all blocks from the starting to the end block
	for i = start_block_idx, end_block_idx do
		--logs
		log1:logprint("", "inside the for loop, i="..i)
		--if the block exists
		if iblock.content[i] then
			--logs
			log1:logprint("", "block exists, so get the block")
			--gets the block; the block_id is the ith entry of iblock contents table
			block = get_block(iblock.content[i])
			--sends the block to GC
			gc_block(iblock.content[i])
		--if not
		else
			--logs
			log1:logprint("", "block doesnt exists, so create the block")
			--the block initially is an empty string
			block = ""
		end
		--logs
		log1:logprint(".RAW_DATA", "remaining_buf=\""..remaining_buf.."\"")
		log1:logprint("", "size of remaining_buf + block_offset="..(#remaining_buf+block_offset)..", block_size="..block_size)
		--if the size of the remaining buffer + the block offset is bigger than a full block size (it means we need to trunk the remaining buffer cause it does not fit in one block)
		if (#remaining_buf+block_offset) > block_size then
			--logs
			log1:logprint("", "more than block size")
			--fills out to_write_in_block with enough data to reach the end of the block
			to_write_in_block = string.sub(remaining_buf, 1, (block_size - block_offset))
			--cuts that data from the remaining buffer
			remaining_buf = string.sub(remaining_buf, (block_size - block_offset)+1, -1)
		--if not (all the remaining buffer fits in the block)
		else
			--logs
			log1:logprint("", "less than block size")
			--to_write_in_block is equal to the remaining buffer
			to_write_in_block = remaining_buf
		end
		--logs
		log1:logprint(".RAW_DATA", "block=\""..block.."\"")
		log1:logprint(".RAW_DATA", "to_write_in_block=\""..to_write_in_block.."\"")
		log1:logprint("", "block_offset="..block_offset..", size of to_write_in_block="..#to_write_in_block)
		--inserts the to_write_in_block segment into the block. TODO: CHECK IF THE +1 AT THE END IS OK
		block = string.sub(block, 1, block_offset)..to_write_in_block..string.sub(block, (block_offset + #to_write_in_block + 1))
		--logs
		log1:logprint(".RAW_DATA", "now block=\""..block.."\"")
		--the blockID is the hash of the iblock number concatenated with the block data
		block_id = hash_string(tostring(iblock.ino)..block)
		--logs
		log1:logprint("", "about to put the block", "blockID="..block_id)
		--puts the block
		put_block(block_id, block)
		--logs
		log1:logprint("", "block written, about to change iblock", "iblock.content["..i.."]="..tostring(iblock.content[i]))
		--inserts the new block number in the contents table
		iblock.content[i] = block_id
		--the block offset is set to 0
		--logs
		log1:logprint("", "iblock changed,", "iblock.content["..i.."]="..tostring(iblock.content[i]))
		block_offset = 0
		--logs
		log1:logprint("", "end of a cycle")
	end
	--if the size changed
	if size_changed then
		--changes the metadata in the iblock
		iblock.size = offset+size
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	return iblock
end

--function cmn_truncate: truncates a file to a given size, or appends zeros if the requested size is bigger than the original
local function cmn_truncate(iblock, size)
	--starts the logger
	local log1 = start_logger(".COMMON_OP .READ_WRITE_OP cmn_truncate", "INPUT", "size="..size)
	--prints the iblock
	log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
	--stores the size reported by the iblock in the variable orig_size
	local orig_size = iblock.size
	--if the original size is less than the new size, append zeros
	if orig_size < size then
		local buf = string.rep("\0", size - orig_size)
		log1:logprint_flush("END", "calling cmn_write")
		return cmn_write(buf, orig_size, iblock)
	end
	--calculates the index (in the iblock contents table) of the block where the pruning takes place
	local block_idx = math.floor((size - 1) / block_size) + 1
	--calculates the offset on the block
	local rem_offset = size % block_size
	--logs
	log1:logprint("", "orig_size="..orig_size..", new_size="..size..", block_idx="..block_idx..", rem_offset="..rem_offset)
	--from the last block until the second last to be deleted (decremented for loop)
	for i=#iblock.content, block_idx+1,-1 do
		--logs
		log1:logprint("", "about to remove block", "iblock.content["..i.."]="..tostring(iblock.content[i]))
		--sends the block to GC
		gc_block(iblock.content[i])
		--removes the block from the iblock contents
		table.remove(iblock.content, i)
	end
	--logs
	log1:logprint("", "about to change block", "iblock.content["..block_idx.."]="..tostring(iblock.content[block_idx]))
	--if the remainding offset is 0
	if rem_offset == 0 then
		log1:logprint("", "last block must be empty, so we delete it")
		--removes the block from the iblock contents
		table.remove(iblock.content, block_idx)
	--if not, we must truncate the block and rewrite it
	else
		--logs
		log1:logprint("", "last block will not be empty")
		--gets the last block
		local last_block = get_block(iblock.content[block_idx])
		--logs
		log1:logprint(".RAW_DATA", "it already has this=\""..last_block.."\"")
		local write_in_last_block = string.sub(last_block, 1, rem_offset)
		--logs
		log1:logprint(".RAW_DATA", "and we change it to this=\""..write_in_last_block.."\"")
		--the blockID is the hash of the iblock number concatenated with the block data
		local block_id = hash_string(tostring(iblock.ino)..write_in_last_block)
		--puts the block
		put_block(block_id, write_in_last_block)
		--replaces with the new blockID the entry blockIdx in the contents table
		iblock.content[block_idx] = block_id
	end
	--eitherway, sends the block to GC
	gc_block(iblock.content[block_idx])
	--updates the size
	iblock.size = size
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns the iblock
	return iblock
end


--START MAIN ROUTINE

--starts the logger
init_logger(logfile, logrules, logbatching, global_details, global_timestamp, global_elapsed)
--starts the logger
local mainlog = start_logger("MAIN", "starting FlexiFS")
--takes userID, groupID, etc., from FUSE context
local uid, gid, pid, puid, pgid = fuse.context()
--logs
mainlog:logprint("", "FUSE context taken", "uid="..tostring(uid)..", gid="..tostring(gid)..", pid="..tostring(pid)..", puid="..tostring(puid)..", pgid="..tostring(pgid))
--the session register is identified with the hash of the string session_id
--NOTE: thinking of have a register for each user, but then, iblock number = uid + sessionID + seq_number, instead of only sessionID + seq_number
local session_reg_key = hash_string("session_id")
--logs
mainlog:logprint("", "session_register="..session_reg_key)
--gets the session register from the DB
session_id = tonumber(send_get(DB_URL, session_reg_key, "paxos"))
--increments the sessionID. NOTE + TODO: the read + increment + write of the session register is not an atomic process
session_id = (1 + (session_id or 0)) % 10000
--logs
mainlog:logprint("", "new sessionID="..session_id)
--puts the new sessionID into the DB
send_put(DB_URL, session_reg_key, "paxos", session_id)
--looks if the root_dblock is already in the DB
local root_dblock = get_dblock(1)
--logs
mainlog:logprint("", "root_dblock retrieved")
--if there isn't any
if not root_dblock then
	--logs
	mainlog:logprint(".FILE_IBLOCK_OP", "no root_dblock, creating root")
	--creates the root dblock
	root_dblock = {
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
		ctime = os.time(),
		--content is empty
		content = {}
	}
	--logs
	mainlog:logprint(".FILE_IBLOCK_OP", "about to put the root file")
	--puts root file
	put_file("/", 1)
	--logs
	mainlog:logprint(".FILE_IBLOCK_OP", "about to put the root dblock")
	--puts root iblock
	put_dblock(1, root_dblock)
end

--the FlexiFS object, with all the FUSE methods
local flexifs = {

	--function pulse: used in Lua memFS for "pinging"
	pulse = function()
		--starts the logger
		local log1 = start_end_logger(".FILE_MISC_OP pulse")
	end,

	--GENERAL FILE OPERATIONS

	--function mknod: creates a new regular, special or fifo file
	mknod = function(self, filename, mode, rdev)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP mknod", "INPUT", "filename="..filename..", mode="..mode..", rdev="..rdev)
		--flags:
		local flags = {
			CHECK_EXIST=true,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_mk_file")
		--makes a file with iblock_n=nil (creates iblock), number_links=1, size=0, dev=rdev and returns the result of the operation
		return cmn_mk_file(filename, nil, flags, mode, 1, 0, rdev)
	end,

	--function getattr: gets the attributes of a requested file
	getattr = function(self, filename)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP getattr", "INPUT", "filename="..filename, true)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_getattr")
		--returns the attributes of a file
		return cmn_getattr(iblock)
	end,

	--function fgetattr: gets the attributes of a requested file
	fgetattr = function(self, filename, iblock, ...)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP fgetattr", "INPUT", "filename="..filename)
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_getattr")
		--returns the attributes of a file
		return cmn_getattr(iblock)
	end,

	--function listxattr: lists the extended attributes of a file
	listxattr = function(self, filename, size)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP listxattr", "INPUT", "filename="..filename..", size="..size)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--initializes xattr_list as an empty table
		local xattr_list = {}
		--for each of the entries of the xattr table in the iblock's metadata
		for i,v in pairs(iblock.xattr) do
			--inserts the name of the extended attribute in the list (converts hashmap into array)
			table.insert(xattr_list, i)
		end
		log1:logprint(".TABLE", "list of extended attributes filled", tbl2str("xattr_list", 0, xattr_list))
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0 and the concatenation of xattr_list, separating the entries with 0's
		return 0, table.concat(xattr_list, "\0").."\0"
	end,

	--function removexattr: removes an extended attribute from a file
	removexattr = function(self, filename, xattr_name)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP removexattr", "INPUT", "filename="..filename..", xattr_name="..xattr_name)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--deletes the entry with name xattr_name
		iblock.xattr[xattr_name] = nil
		--puts the iblock
		put_iblock(iblock.ino, iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function setxattr: sets an extended attribute
	setxattr = function(self, filename, xattr_name, val, flags)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP setxattr", "INPUT", "filename="..filename..", xattr_name="..xattr_name..", value="..tostring(val))
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--sets the extended attribute to val
		iblock.xattr[xattr_name] = val
		--puts the iblock
		put_iblock(iblock.ino, iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function getxattr: gets the value of an extended attribute
	getxattr = function(self, filename, xattr_name, size)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP getxattr", "INPUT", "filename="..filename)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0 and the value of the extended attribute (if not found, returns an empty string)
		return 0, iblock.xattr[xattr_name] or ""
	end,

	--function chown: changes the owner and/or the group of a file
	chown = function(self, filename, uid, gid)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP chown", "INPUT", "filename="..filename..", uid="..tostring(uid)..", gid="..tostring(gid))
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--changes the uid and gid
		iblock.uid = uid
		iblock.gid = gid
		--updates the iblock on the DB
		put_iblock(iblock.ino, iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function chmod: changes the mode of a file
	chmod = function(self, filename, mode)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP chmod", "INPUT", "filename="..filename..", mode="..mode)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--changes the mode
		iblock.mode = mode
		--updates the iblock on the DB
		put_iblock(iblock.ino, iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	utime = function(self, filename, atime, mtime)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP utime", "INPUT", "filename="..filename.."atime="..atime.."mtime="..mtime)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--changes the times
		iblock.atime = atime
		iblock.mtime = mtime
		--updates the iblock on the DB
		put_iblock(iblock.ino, iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--DIRECTORY OPERATIONS

	--function mkdir: creates a directory
	mkdir = function(self, filename, mode, ...)
		--starts the logger
		local log1 = start_logger(".FUSE_API .DIR_OP mkdir", "INPUT", "filename="..filename..", mode="..mode)
		--flags:
		local flags = {
			CHECK_EXIST=true,
			IS_DIR=true,
			UPDATE_PARENT=true
		}
		--the mode is mixed wit the flag S_IFDIR
		mode = set_bits(mode, S_IFDIR)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_mk_file")
		--makes a file with iblock_n=nil (creates iblock), number_links=2 and returns the result of the operation. TODO: CHECK IF SIZE IS NOT block_size
		return cmn_mk_file(filename, nil, flags, mode, 2)
	end,

	--function opendir: opens a directory
	opendir = function(self, filename)
		--starts the logger
		local log1 = start_logger(".FUSE_API .DIR_OP opendir", "INPUT", "filename ="..filename)
		--gets the dblock from the DB
		local dblock = get_dblock_from_filename(filename)
		--if the dblock does not exist (ERROR), returns ENOENT
		if not dblock then
			log1:logprint_flush("END", "", "dblock does not exist, returning ENOENT")
			return ENOENT
		end
		--logs
		log1:logprint(".TABLE", "dblock retrieved", tbl2str("dblock", 0, dblock))
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0, and the dblock
		return 0, dblock
	end,

	--function readdir: retrieves the contents of a directory
	readdir = function(self, filename, offset, dblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .DIR_OP readdir", "INPUT", "filename="..filename..", offset="..offset)
		--prints the dblock
		log1:logprint(".TABLE", "INPUT", tbl2str("dblock", 0, dblock))
		--looks for the dblock
		local dblock = get_dblock_from_filename(filename)
		--if the dblock does not exist (ERROR), returns ENOENT
		if not dblock then
			log1:logprint_flush("END", "", "dblock does not exist, returning ENOENT")
			return ENOENT
		end
		--logs
		log1:logprint(".TABLE", "dblock retrieved", tbl2str("dblock", 0, dblock))
		--starts the file list with "." and ".."
		local file_list={'.', '..'}
		--for each entry in content, adds it in the file list
		for i,v in pairs(dblock.content) do
			table.insert(file_list, i)
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0 and the list of files
		return 0, file_list
	end,

	--function fsyncdir: synchronizes a directory
	fsyncdir = function(self, filename, isdatasync, dblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP fsyncdir", "INPUT", "filename="..filename..", isdatasync="..tostring(isdatasync))
		--prints the dblock
		log1:logprint(".TABLE", "INPUT", tbl2str("dblock", 0, dblock))
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function releasedir: closes a directory
	releasedir = function(self, filename, dblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .DIR_OP releasedir", "INPUT", "filename="..filename)
		--prints the dblock
		log1:logprint(".TABLE", "INPUT", tbl2str("dblock", 0, dblock))
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function rmdir: removes a directory from the FS
	rmdir = function(self, filename)
		--starts the logger
		local log1 = start_logger(".FUSE_API .DIR_OP rmdir", "INPUT", "filename="..filename)
		--flags:
		local flags = {
			IS_DIR = true,
			UPDATE_PARENT = true
		}
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_rm_file")
		--removes the file from the FS and returns the result of the operation
		return cmn_rm_file(filename, flags)

	end,

	--REGULAR FILE OPERATIONS

	--function create: creates and opens a regular file. TODO CHECK if i can "not update" iblock at creation time
	create = function(self, filename, mode, create_flags, ...)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP create", "INPUT", "filename="..filename..", type create flags="..type(create_flags)..", mode="..mode)
		--flags:
		local flags = {
			CHECK_EXIST=false,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--the file is regular (S_IFREG set to true)
		mode = set_bits(mode, S_IFREG)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_mk_file")
		--makes a file with iblock_n=nil (creates iblock)
		local ok, iblock = cmn_mk_file(filename, nil, flags, mode)
		if ok == 0 then
			iblock.open_sessions = 1
		end
		return ok, iblock
	end,

	--function open: opens a file for read/write operations
	open = function(self, filename, flags)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP open", "INPUT", "filename="..filename..", flags="..flags, true)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		log1:logprint(".MEGA_DEBUG .TABLE", "iblock retrieved", tbl2str("iblock", 0, iblock))
		--m is the remainder flags divided by 4
		local mode = flags % 4
		--takes userID, groupID, etc., from FUSE context
		local uid, gid, pid, puid, pgid = fuse.context()
		--logs
		log1:logprint(".MEGA_DEBUG", "FUSE context taken", "uid="..tostring(uid)..", gid="..tostring(gid)..", pid="..tostring(pid)..", puid="..tostring(puid)..", pgid="..tostring(pgid))
		log1:logprint(".MEGA_DEBUG", "mode="..mode)
		--increments the number of open sessions
		iblock.open_sessions = iblock.open_sessions + 1
		log1:logprint(".MEGA_DEBUG .TABLE", "iblock changed", tbl2str("iblock", 0, iblock))
		
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0 and the iblock
		return 0, iblock
	end,

	--function read: reads data from an open file. TODO: CHANGE MDATE and ADATE WHEN READING/WRITING
	read = function(self, filename, size, offset, iblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .READ_WRITE_OP read", "INPUT", "filename="..filename..", size="..size.."..offset="..offset)
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_read")
		--performs a cmn_read operation and returns the result of the operation
		return cmn_read(size, offset, iblock)
	end,

	--function write: writes data into a file. TODO: CHANGE MDATE and ADATE WHEN WRITING
	write = function(self, filename, buf, offset, iblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .READ_WRITE_OP write", "INPUT", "filename="..filename..", offset="..offset)
		--prints the buffer
		log1:logprint(".RAW_DATA", "INPUT", "buf=\""..buf.."\"")
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--performs a cmn_write operation (puts blocks but does not update iblock in the DB - close-to-open consistency)
		iblock = cmn_write(buf, offset, iblock)
		--any write operation changes the iblock (at least the mtime changes. TODO: check when buf is an empty string)
		iblock.changed = true
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns the size of the written buffer
		return #buf, iblock
	end,

	--function flush: cleans local record about an open file
	flush = function(self, filename, iblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP flush", "INPUT", "filename="..filename, true)
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--if the iblock changed
		if iblock.changed then
			--TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function ftruncate: truncates a file using directly the iblock as reference.
	--TODO: if (dirent.open or 0) < 1 then mnode.flush_node(dirent, path, true) CONSIDER THIS LINE OF CODE FROM MEMFS.LUA IN ALL FILE MANIPULATIONS
	ftruncate = function(self, filename, size, iblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP ftruncate", "INPUT", "filename="..filename..", size="..size)
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--performs a cmn_truncate operation (does not update iblock in the DB - close-to-open consistency)
		iblock = cmn_truncate(iblock, size)
		--any truncate operation changes the iblock (at least the mtime changes. TODO: check when orig_size == size)
		iblock.changed = true
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0, iblock
	end,

	--function fsync: ...
	fsync = function(self, filename, isdatasync, iblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP fsync", "INPUT", "filename="..filename..", isdatasync="..isdatasync)
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--TODO: PA DESPUES
		--[[
		mnode.flush_node(iblock, filename, false) 
		if isdatasync and iblock.changed then 
			mnode.flush_data(iblock.content, iblock, filename) 
		end
		--]]
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function release: closes an open file
	release = function(self, filename, iblock)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP release", "INPUT", "filename="..filename)
		--prints the iblock
		log1:logprint(".TABLE", "INPUT", tbl2str("iblock", 0, iblock))
		--decrements the number of open sessions
		iblock.open_sessions = iblock.open_sessions - 1
		--if the number of open sessions reaches 0
		if iblock.open_sessions == 0 and iblock.changed then
			log1:logprint("", "the number of open sessions reached 0 and the iblock has changed; must be updated in the DB")
			--flag "changed" is cleared
			iblock.changed = nil
			--puts iblock into DB
			put_iblock(iblock.ino, iblock)
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function truncate: truncates a file to a given size, or appends zeros if the requested size is bigger than the original
	truncate = function(self, filename, size)
		--starts the logger
		local log1 = start_logger(".FUSE_API .FILE_MISC_OP truncate", "INPUT", "filename="..filename.."size="..size)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--performs a cmn_truncate operation (does not update iblock in the DB - close-to-open consistency)
		iblock = cmn_truncate(iblock, size)
		--updates iblock in DB
		put_iblock(iblock.ino, iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function rename: moves/renames a file
	rename = function(self, from, to)
		--starts the logger
		local log1 = start_logger(".FUSE_API .MV_CP_OP rename", "INPUT", "from="..from..", to="..to)
		--if the "from" file is equal to the "to" file. TODO: the man page says it should do that, but BASH's "mv" sends an error
		if from == to then
			log1:logprint_flush("END", "from and to are the same, nothing to do here")
			return 0
		end
		--gets "from" iblock from DB
		local from_iblock = get_iblock_from_filename(from)
		--if the "from" iblock does not exist (ERROR), returns ENOENT
		if not from_iblock then
			log1:logprint_flush("ERROR END", "", "\"from\" iblock does not exist, returning ENOENT")
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
		--only if "to" and "from" are different (avoids writing on parent's dblock twice, for the sake of efficiency)
		if to_dir ~= from_dir then
			--updates the to_parent dblock, because the contents changed
			put_iblock(to_parent.ino, to_parent)
		end
		--updates the from_parent's dblock, because the contents changed
		put_iblock(from_parent.ino, from_parent)
		--puts the "to" file, because it's new
		put_file(to, from_iblock.ino)
		--deletes the "from" file
		del_file(from)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function link: makes a hard link
	link = function(self, from, to, ...)
		--starts the logger
		local log1 = start_logger(".FUSE_API .LINK_OP link", "INPUT", "from="..from..", to="..to, true)
		--if the "from" file is equal to the "to" file. TODO: the man page says it should do that, but BASH's "mv" sends an error
		if from == to then
			log1:logprint_flush("END", "from and to are the same, nothing to do here")
			return 0
		end
		--gets "from" iblock from DB
		local from_iblock = get_iblock_from_filename(from)
		--prints iblock
		log1:logprint(".TABLE", "\"from\" iblock retrieved", tbl2str("iblock", 0, iblock))
		--if the "from" iblock does not exist (ERROR), returns ENOENT
		if not from_iblock then
			log1:logprint_flush("ERROR END", "", "\"from\" iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--flags:
		local flags = {
			CHECK_EXIST=false,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--makes a file with iblock_n=iblock.ino (does not creates iblock)
		cmn_mk_file(to, from_iblock.ino, flags)
		--increments the number of links in from_iblock
		from_iblock.nlink = from_iblock.nlink + 1
		--prints iblock
		log1:logprint(".TABLE", "new \"from\" iblock", tbl2str("iblock", 0, iblock))
		--updates iblock in DB, because nlink was incremented
		put_iblock(from_iblock.ino, from_iblock)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--returns 0
		return 0
	end,

	--function unlink: deletes a link to an iblock
	unlink = function(self, filename, ...)
		--starts the logger
		local log1 = start_logger(".FUSE_API .LINK_OP unlink", "INPUT", "filename="..filename)
		--flags:
		local flags = {
			IS_DIR = false,
			UPDATE_PARENT = true
		}
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "calling cmn_rm_file")
		--removes the file from the FS and returns the result of the operation
		return cmn_rm_file(filename, flags)
	end,

	--function symlink: makes a symbolic link
	symlink = function(self, from, to)
		--starts the logger
		local log1 = start_logger(".FUSE_API .LINK_OP symlink", "INPUT", "from="..from.."to="..to, true)
		--flags:
		local flags = {
			CHECK_EXIST=true,
			IS_DIR=false,
			UPDATE_PARENT=true
		}
		--the mode for symbolic link is 777 with the flag S_IFLNK set to true
		local mode = S_IFLNK + mk_mode(7,7,7)
		--logs END of the function and flushes all logs
		log1:logprint_flush("END")
		--makes a file with iblock_n=nil (creates iblock), number_links=1, size=0, dev=rdev, content is the string "from" and returns the result of the operation
		return cmn_mk_file(to, nil, flags, mode, 1, string.len(from), 0, {from})
	end,

	--function readlink: reads a symbolic link
	readlink = function(self, filename)
		--starts the logger
		local log1 = start_logger(".FUSE_API LINK_OP readlink", "INPUT", "filename="..filename)
		--gets iblock from DB
		local iblock = get_iblock_from_filename(filename)
		--if the iblock does not exist (ERROR), returns ENOENT
		if not iblock then
			log1:logprint_flush("ERROR END", "", "iblock does not exist, returning ENOENT")
			return ENOENT
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "symlink="..iblock.content[1])
		--returns 0 and the symbolic link
		return 0, iblock.content[1]
	end,

	--function access: ...
	access = function(...)
		--starts the logger
		local log1 = start_end_logger(".FILE_MISC_OP access")
		--returns 0
		return 0
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
mainlog:logprint("", "FlexiFS object created, about to define FUSE options")
--fills the fuse options out
fuse_opt = {'flexifs', 'mnt', '-f', '-s', '-d', '-oallow_other'}
--logs
mainlog:logprint("", "FUSE options defined")
--if the amount of argumenst is less than two
if select('#', ...) < 2 then
	--prints usage
	print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
	--exits
	os.exit(1)
end
--logs
mainlog:logprint_flush("END", "about to execute fuse.main")
--cleans the logger
mainlog = nil
--starts FUSE
fuse.main(flexifs, {...})