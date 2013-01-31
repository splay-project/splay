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
local fuse = require 'fuse'
--distdb-client contains APIs send-get, -put, -delete to communicate with the distDB
local dbclient = require 'distdb-client'
--lbinenc is used for serialization
local serializer = require'splay.lbinenc'
--crypto is used for hashing
local crypto = require'crypto'
--splay.misc used for misc.time
local misc = require'splay.misc'
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

local block_size = 256*1024
local blank_block=string.rep("0", block_size)
local open_mode={'rb','wb','rb+'}

--consistency type can be "evtl_consistent", "paxos" or "consistent"
local consistency_type = "consistent"
--the URL of the Entry Point to the distDB
local db_url = "127.0.0.1:15272"


--LOCAL VARIABLES FOR LOGGING

local log_domains = {
	MAIN_OP=false,
	DB_OP=true,
	FILE_INODE_OP=false,
	DIR_OP=false,
	LINK_OP=false,
	READ_WRITE_OP=true,
	FILE_MISC_OP=false,
	MV_CP_OP=false
}
local _LOGMODE = "file_efficient"
local _LOGFILE = "/home/unine/logsplayfuse.txt"
local log_tbl = {}
local to_report_t = {}

--LOGGING FUNCTIONS

--if we are just printing in screen
if _LOGMODE == "print" then
	write_log_line = print
	write_last_log_line = print
--if we print to a file
elseif _LOGMODE == "file" then
	write_log_line = function(message, ...)
		local logfile1 = io.open(_LOGFILE,"a")
		logfile1:write(message)
		for i=1,arg["n"] do
			logfile1:write("\t"..tostring(arg[i]))
		end
		logfile1:write("\n")
		logfile1:close()
	end
	write_last_log_line = write_log_line
--if we want to print to a file efficiently
elseif _LOGMODE == "file_efficient" then
	--write_log_line adds an entry to the logging table
	write_log_line = function(message, ...)
		table.insert(log_tbl, message)
		for i=1,arg["n"] do
			table.insert(log_tbl, "\t"..tostring(arg[i]))
		end
		table.insert(log_tbl, "\n")
	end
	--write_last_log_line writes the table.concat of all the log lines in a file and cleans the logging table
	write_last_log_line = function(message, ...)
		local logfile1 = io.open(_LOGFILE,"a")
		write_log_line(message, ...)
		logfile1:write(table.concat(log_tbl))
		logfile1:close()
		log_tbl = {}
	end
else
	--empty functions
	write_log_line = function(message, ...) end
	write_last_log_line = function(message, ...) end
end

--function logprint: function created to send log messages; it handles different log domains, like DB_OP (Database Operation), etc.
function logprint(log_domain, message, ...)
	--if logging in the proposed log domain is ON
	if log_domains[log_domain] then
		write_log_line(message, ...)
	end
end

function last_logprint(log_domain, message, ...)
	--if logging in the proposed log domain is ON
	if log_domains[log_domain] then
		--writes a log line with the message
		write_last_log_line(message, ...)
	end
end

function table2str(name, order, input_table)
	--if input_table is nil
	if not input_table then
		--return a string indicating it
		return name.." = nil"
	end
	--if it is a string or a number, return it as it is
	if type(input_table) == "string" or type(input_table) == "number" then
		return name.." = "..input_table
	end

	if type(input_table) == "boolean" then
		if input_table then
			return name.." = true"
		else
			return name.." = false"
		end
	end

	--creates a table to store all strings; more efficient to do a final table.concat than to concatenate all the way
	local output_tbl = {"table: "..name.."\n"}
	--indentation is a series of n x "\t" (tab characters), where n = order
	local indentation = string.rep("\t", order)
	--for all elements of the table
	for i,v in pairs(input_table) do
		--the start of the line is the indentation + table_indx
		table.insert(output_tbl, indentation..i.." = ")
		--if the value is a string or number, just concatenate
		if type(v) == "string" or type(v) == "number" then
			table.insert(output_tbl, v.."\n")
		--if it's a boolean, concatenate "true" or "false" according to the case
		elseif type(v) == "boolean" then
			if v then
				table.insert(output_tbl, "true\n")
			else
				table.insert(output_tbl, "false\n")
			end
		--if it's a table, repeat table2str a level deeper
		elseif type(v) == "table" then
			table.insert(output_tbl, "table:\n")
			table.insert(output_tbl, table2str("", order+1, v))
		--if v is nil, concatenate "nil"
		elseif not v then
			table.insert(output_tbl, "nil\n")
		--if v is something else, print type(v) e.g. functions
		else
			table.insert(output_tbl, "type: "..type(v).."\n")
		end
	end
	--returns the concatenation of all lines
	return table.concat(output_tbl)
end


--DB OPERATIONS

--function write_in_db: writes an element into the underlying DB
local function write_in_db(unhashed_key, value)
	--timestamp logging
	local start_time = misc.time()
	--logs entrance
	logprint("DB_OP", "write_in_db: START unhashed_key="..unhashed_key)
	--creates the DB Key by SHA1-ing the concatenation of the type of element and the unhashed key (e.g. the filename, the inode number)
	local db_key = crypto.evp.digest("sha1", unhashed_key)
	--logs
	--logprint("DB_OP", "write_in_db: value = ", value)
	--timestamp logging
	logprint("DB_OP", "write_in_db: GOING_TO_SEND unhashed_key="..unhashed_key.." db_key="..db_key.." elapsed_time="..(misc.time()-start_time))
	--sends the value
	local ok_put = send_put(db_url, db_key, consistency_type, value)
	--flushes all timestamp logs
	last_logprint("DB_OP", "write_in_db: END unhashed_key="..unhashed_key.." db_key="..db_key.." elapsed_time="..(misc.time()-start_time))
	--returns the result of the PUT operation (true=successful or false=failed)
	return ok_put
end

--function read_from_db: reads an element from the underlying DB
local function read_from_db(unhashed_key)
	--timestamp logging
	local start_time = misc.time()
	--logs entrance
	logprint("DB_OP", "read_in_db: START unhashed_key="..unhashed_key)
	--creates the DB Key by SHA1-ing the concatenation of the type of element and the unhashed key (e.g. the filename, the inode number)
	local db_key = crypto.evp.digest("sha1", unhashed_key)
	--logs
	logprint("DB_OP", "read_in_db: GOING_TO_SEND unhashed_key="..unhashed_key.." db_key="..db_key.." elapsed_time="..(misc.time()-start_time))
	--sends a GET command to the DB
	local ok_get, value_get = send_get(db_url, db_key, consistency_type)
	--flushes all timestamp logs
	last_logprint("DB_OP", "read_in_db: END unhashed_key="..unhashed_key.." db_key="..db_key.." elapsed_time="..(misc.time()-start_time))
	--returns the result of the GET operation (true=successful or false=failed) and the returned value
	return ok_get, value_get
end

--function delete_from_db: deletes an element from the underlying DB
local function delete_from_db(unhashed_key)
	--timestamp logging
	local start_time = misc.time()
	--logs entrance
	logprint("DB_OP", "delete_from_db: START unhashed_key="..unhashed_key)
	--creates the DB Key by SHA1-ing the concatenation of the type of element and the unhashed key (e.g. the filename, the inode number)
	local db_key = crypto.evp.digest("sha1", unhashed_key)
	--logs
	logprint("DB_OP", "delete_from_in_db: GOING_TO_SEND unhashed_key="..unhashed_key.." db_key="..db_key.." elapsed_time="..(misc.time()-start_time))
	--sends a DELETE command to the DB
	local ok_delete = send_delete(db_url, db_key, consistency_type)
	--flushes all timestamp logs
	last_logprint("DB_OP", "delete_from_db: END unhashed_key="..unhashed_key.." db_key="..db_key.." elapsed_time="..(misc.time()-start_time))
	--returns the result of the DELETE operation (true=successful or false=failed)
	return ok_delete
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


--MISC FUNCTIONS

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

	last_logprint("FILE_INODE_OP", "decode_acl: START, s=", s)

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
	logprint(log_domain, function_name..": START, owner=", owner, ", group=", group, ", world=", world)
	logprint(log_domain, table2str("sticky", 0 ,sticky))
	--if sticky is not specified, fills it out with 0
	sticky = sticky or 0
	--result mode is the combination of the owner, group, world rights and the sticky mode
	local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID
	--flushes all logs
	last_logprint(log_domain, function_name..": returns result_mode=", result_mode)
	--returns the mode
	return result_mode
end


--FS TO DB FUNCTIONS

--function get_block: gets a block from the DB
function get_block(block_n)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "get_block"
	local log_domain, function_name = "FILE_INODE_OP", "get_block"
	--checks input errors
	--safety if: if the block_n is not a number, return with error
	if type(block_n) ~= "number" then
		last_logprint(log_domain, function_name..": block_n not a number, returning nil")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, block_n=", block_n)
	--reads the file element from the DB
	local ok_read_from_db_block, data = read_from_db("block:"..block_n)
	--if the reading was not successful
	if not ok_read_from_db_block then
		--reports the error, flushes all logs and return nil
		last_logprint(log_domain, function_name..": ERROR, read_from_db of block was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
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
		last_logprint(log_domain, function_name..": inode_n not a number, returning nil")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, inode_n=", inode_n)
	--reads the inode element from the DB
	local ok_read_from_db_inode, inode_serialized = read_from_db("inode:"..inode_n)
	--logs
	logprint(log_domain, function_name..": read_from_db returned=")
	logprint(log_domain, table2str("ok_read_from_db_inode", 0, ok_read_from_db_inode))
	--logprint(log_domain, table2str("inode_serialized", 0, inode_serialized))
	--if the reading was not successful
	if not ok_read_from_db_inode then
		--reports the error and returns nil
		last_logprint(log_domain, function_name..": ERROR, read_from_db of inode was not OK")
		return nil
	end
	--if the requested record is empty
	if not inode_serialized then
		--reports the error and returns nil
		last_logprint(log_domain, function_name..": inode_serialized is nil, returning nil")
		return nil
	end
	--logs
	logprint(log_domain, function_name..": trying to serializer_decode, type of inode_serialized=", type(inode_serialized))
	--deserializes the inode
	local inode = serializer.decode(inode_serialized)
	--logs
	logprint(log_domain, function_name..": read_from_db returned")
	--flushes all logs
	last_logprint(log_domain, table2str("inode", 0, inode))
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
		last_logprint(log_domain, function_name..": filename not a valid string, returning nil")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, filename=", filename)
	--reads the file element from the DB
	local ok_read_from_db_file, inode_n = read_from_db("file:"..filename)
	--if the reading was not successful
	if not ok_read_from_db_file then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, read_from_db of file was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": inode_n = ", inode_n)
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
		last_logprint(log_domain, function_name..": filename not a valid string, returning nil")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, filename=", filename)
	--the inode number is extracted by calling get_inode_n
	local inode_n = get_inode_n(filename)
	--flushes all logs
	last_logprint(log_domain, function_name..": inode number retrieved inode_n=", inode_n)
	--returns the corresponding inode
	return get_inode(inode_n)
end

--function put_block: puts a block element into the DB
function put_block(block_n, data)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_INODE_OP", "put_block"
	--checks input errors
	--if block_n is not a number
	if type(block_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": block_n not a number, returning nil")
		return nil
	end
	--if data is not a string
	if type(data) ~= "string" then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": data not a string, returning nil")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, block_n=", block_n, "data size=", string.len(data))
	--writes the block in the DB
	local ok_write_in_db_block = write_in_db("block:"..block_n, data)
	--if the writing was not successful
	if not ok_write_in_db_block then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, write_in_db of block was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
	--returns true
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
		last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--if inode is not a table
	if type(inode) ~= "table" then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, inode not a table")
		return nil
	end	

	--logs entrance
	logprint(log_domain, function_name..": START, inode_n=", inode_n)
	logprint(log_domain, table2str("inode", 0, inode))

	--writes the inode in the DB
	local ok_write_in_db_inode = write_in_db("inode:"..inode_n, serializer.encode(inode))
	--if the writing was not successful
	if not ok_write_in_db_inode then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, write_in_db of inode was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
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
		last_logprint(log_domain, function_name..": ERROR, filename not a string")
		return nil
	end
	--if inode_n is not a number
	if type(inode_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, filename=", filename..", inode_n=", inode_n)

	--writes the file in the DB
	local ok_write_in_db_file = write_in_db("file:"..filename, inode_n)
	--if the writing was not successful
	if not ok_write_in_db_file then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, write_in_db of file was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
	--returns true
	return true
end

--function delete_block: deletes a block element from the DB
function delete_block(block_n)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "delete_block"
	local log_domain, function_name = "FILE_INODE_OP", "delete_block"
	--checks input errors
	--if block_n is not a number
	if type(block_n) ~= "number" then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, block_n not a number")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, block_n=", block_n)
	--deletes the block from the DB
	local ok_delete_from_db_block = delete_from_db("block:"..block_n)
	--if the deletion was not successful
	if not ok_delete_from_db_block then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
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
		last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, inode_n=", inode_n)
	--reads the inode element from the DB
	local inode = get_inode(inode_n)
 	--for all the blocks refered by the inode
	for i,v in ipairs(inode.content) do
		--deletes the blocks. TODO: NOT CHECKING IF SUCCESSFUL
		delete_from_db("block:"..v)
	end
	--deletes the inode from the DB
	local ok_delete_from_db_inode = delete_from_db("inode:"..inode_n)
	--if the deletion was not successful
	if not ok_delete_from_db_inode then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
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
		last_logprint(log_domain, function_name..": ERROR, inode_n not a number")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, inode_n=", inode_n)
	--deletes the inode from the DB
	local ok_delete_from_db_inode = delete_from_db("inode:"..inode_n)
	--if the deletion was not successful
	if not ok_delete_from_db_inode then
		--reports the error, flushes all logs and returns nil
		logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
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
		logprint(log_domain, function_name..": ERROR, filename not a string")
		return nil
	end
	--logs entrance
	logprint(log_domain, function_name..": START, filename=", filename)
	--deletes the file element from the DB
	local ok_delete_from_db_file = delete_from_db("file:"..filename)
	--if the deletion was not successful
	if not ok_delete_from_db_file then
		--reports the error, flushes all logs and returns nil
		last_logprint(log_domain, function_name..": ERROR, delete_from_db of inode was not OK")
		return nil
	end
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
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
		logprint(log_domain, function_name..": filename not a valid string, returning ENOENT")
		return ENOENT
	end
	--logs entrance
	logprint(log_domain, function_name..": START, filename=", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--logs
	logprint(log_domain, function_name..": for filename=", filename, " get_inode_from_filename returned =")
	logprint(log_domain, table2str("inode", 0, inode))
	--if there is no inode
	if not inode then
		--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
		logprint(log_domain, function_name..": no inode found, returning ENOENT")
		return ENOENT
	end
	--copies all metadata into the variable x
	local x = inode.meta
	--flushes all logs
	last_logprint(log_domain, function_name..": END")
	--returns 0 (successful), mode, inode number, device, number of links, userID, groupID, size, access time, modif time, creation time
	return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime
end


--logs start
logprint("MAIN_OP", "MAIN: starting SPLAYFUSE")
--takes User and Group ID, etc, from FUSE context
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
	logprint("FILE_INODE_OP", "MAIN: going to put root file")
	--puts root file element
	put_file("/", 1)
	--logs
	logprint("FILE_INODE_OP", "MAIN: going to put root inode")
	--puts root inode element
	put_inode(1, root_inode)
end

--the splayfuse object, with all the FUSE methods
local splayfuse={

--function pulse: used in Lua memFS for "pinging"
pulse=function()
	--logs entrance
	last_logprint("FILE_MISC_OP", "pulse: START")
end,

--function getattr: gets the attributes of a requested file
getattr=function(self, filename)
	--for all the logprint functions: the log domain is "FILE_MISC_OP" and the function name is "getattr"
	local log_domain, function_name = "FILE_MISC_OP", "getattr"
	--logs entrance
	logprint(log_domain, function_name..": START, filename=", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--if there is no inode
	if not inode then
		--reports the error, flushes all logs and returns error code ENOENT (No such file or directory)
		last_logprint(log_domain, function_name..": no inode found, returns ENOENT")
		return ENOENT
	end
	--logs
	logprint(log_domain, function_name..": for filename =", filename, " get_inode_from_filename returned =")
	--flushes all logs
	last_logprint(log_domain, table2str("inode", 0, inode))
	--copies the metadata into the variable x
	local x = inode.meta
	--returns 0 (successful), mode, inode number, device, number of links, userID, groupID, size, access time, modif time, creation time
	return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime
end,

--function opendir: opens a directory AQUI ME QUEDE
opendir=function(self, filename)
	local sleep_count = 1
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "DIR_OP", "opendir"
	--logs entrance
	logprint(log_domain, function_name..": START, filename =", filename)
	--gets the inode from the DB
	local inode = get_inode_from_filename(filename)
	--if there is no inode returns the error code ENOENT (No such file or directory)
	if not inode then
		last_logprint(log_domain, function_name..": no inode found, returns ENOENT")
		return ENOENT
	end
	--logs
	logprint(log_domain, function_name..": for filename =", filename, "get_inode_from_filename returned =")
	last_logprint(log_domain, table2str("inode", 0, inode))
	--else, returns 0, and the inode object
	return 0, inode
end,

readdir=function(self, filename, offset, inode)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "DIR_OP", "readdir"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename = ", filename, ", offset=", offset)
	--looks for the inode; we don't care about the inode on memory (sequential operations condition)
	local inode = get_inode_from_filename(filename)
	logprint(log_domain, function_name..": inode retrieved =")
	logprint(log_domain, table2str("inode", 0, inode))
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
	logprint("DIR_OP", "releasedir: START, filename = ", filename)
	last_logprint("DIR_OP", table2str("inode", 0, inode))
	return 0
end,

--function mknod: not sure what it does, it creates a generic node? when is this called
mknod=function(self, filename, mode, rdev)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "mknod"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename)
	--TODO print mode=mode,rdev=rdev

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
		logprint(log_domain, function_name..": what is parent_parent? = ", parent.parent)
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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "READ_WRITE_OP", "read"
	--logs entrance
	--logprint(log_domain, function_name..": START")
	--logprint(log_domain, function_name..": START, filename=", filename..", size=", size..", offset=", offset, {inode=inode})

	table.insert(to_report_t, function_name..": started\telapsed_time=0\n")
	local start_time = misc.time()

	local inode = get_inode_from_filename(filename)
	--logprint(log_domain, function_name..": inode retrieved =")
	--logprint(log_domain, table2str("inode", 0, inode))
	if not inode then
		return 1
	end

	table.insert(to_report_t, function_name..": inode retrieved\telapsed_time="..(misc.time()-start_time).."\n")

	local start_block_idx = math.floor(offset / block_size)+1
	local rem_start_offset = offset % block_size
	local end_block_idx = math.floor((offset+size-1) / block_size)+1
	local rem_end_offset = (offset+size-1) % block_size

	--logprint(log_domain, function_name..": offset=", offset..", size=", size..", start_block_idx=", start_block_idx)
	--logprint(log_domain, function_name..": rem_start_offset=", rem_start_offset..", end_block_idx=", end_block_idx..", rem_end_offset=", rem_end_offset)

	--logprint(log_domain, function_name..": about to get block", {block_n = inode.content[start_block_idx]})

	table.insert(to_report_t, function_name..": orig_size et al. calculated, size="..size.."\telapsed_time="..(misc.time()-start_time).."\n")

	local block = get_block(inode.content[start_block_idx]) or ""

	local data_t = {}

	table.insert(to_report_t, function_name..": first block retrieved\telapsed_time="..(misc.time()-start_time).."\n")

	if start_block_idx == end_block_idx then
		--logprint(log_domain, function_name..": just one block to read")
		table.insert(data_t, string.sub(block, rem_start_offset+1, rem_end_offset))
	else
		--logprint(log_domain, function_name..": several blocks to read")
		table.insert(data_t, string.sub(block, rem_start_offset+1))

		for i=start_block_idx+1,end_block_idx-1 do
			table.insert(to_report_t, function_name..": getting new block\telapsed_time="..(misc.time()-start_time).."\n")
			block = get_block(inode.content[i]) or ""
			table.insert(data_t, block)
		end

		table.insert(to_report_t, function_name..": getting new block\telapsed_time="..(misc.time()-start_time).."\n")

		block = get_block(inode.content[end_block_idx]) or ""
		table.insert(data_t, string.sub(block, 1, rem_end_offset))
	end

	table.insert(to_report_t, function_name..": finished\telapsed_time="..(misc.time()-start_time).."\n")

	last_logprint(table.concat(to_report_t))

	to_report_t = {}

	return 0, table.concat(data_t)
end,

write=function(self, filename, buf, offset, inode) --TODO CHANGE DATE WHEN WRITING
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "READ_WRITE_OP", "write"
	--logs entrance
	--logprint(log_domain, function_name..": START")
	--logprint(log_domain, function_name..": START, filename=", filename, {buf=buf,offset=offset,inode=inode})
	--logs entrance without reporting buf
	--logprint(log_domain, function_name..": START, filename=", filename, {offset=offset,inode=inode})

	table.insert(to_report_t, function_name..": started\telapsed_time=0\n")
	local start_time = misc.time()

	local inode = get_inode_from_filename(filename)

	--logprint(log_domain, function_name..": inode retrieved =")
	--logprint(log_domain, table2str("inode", 0, inode))
	table.insert(to_report_t, function_name..": inode retrieved\telapsed_time="..(misc.time()-start_time).."\n")
	
	local orig_size = inode.meta.size
	local size = #buf
	
	local start_block_idx = math.floor(offset / block_size)+1
	local rem_start_offset = offset % block_size
	local end_block_idx = math.floor((offset+size-1) / block_size)+1
	local rem_end_offset = ((offset+size-1) % block_size)

	
	--logprint(log_domain, function_name..": orig_size=", orig_size..", offset=", offset..", size=", size..", start_block_idx=", start_block_idx)
	--logprint(log_domain, function_name..": rem_start_offset=", rem_start_offset..", end_block_idx=", end_block_idx..", rem_end_offset=", rem_end_offset)

	--logprint(log_domain, function_name..": about to get block", {block_n = inode.content[start_block_idx]})

	table.insert(to_report_t, function_name..": orig_size et al. calculated, size="..size.."\telapsed_time="..(misc.time()-start_time).."\n")

	local block = nil
	local block_n = nil
	local to_write_in_block = nil
	local block_offset = rem_start_offset
	local blocks_created = (end_block_idx > #inode.content)
	local size_changed = ((offset+size) > orig_size)
	local root_inode = nil
	local remaining_buf = buf

	table.insert(to_report_t, function_name..": calculated more stuff\telapsed_time="..(misc.time()-start_time).."\n")

	if blocks_created then
		root_inode = get_inode(1)
	end

	table.insert(to_report_t, function_name..": root might have been retrieved\telapsed_time="..(misc.time()-start_time).."\n")

	--logprint(log_domain, function_name..": blocks are going to be created? new file is bigger? blocks_created=", blocks_created, "size_changed=", size_changed)
	--logprint(log_domain, function_name..": buf=", buf)

	for i=start_block_idx, end_block_idx do
		--logprint(log_domain, function_name..": im in the for loop, i=", i)
		if inode.content[i] then
			--logprint(log_domain, function_name..": block exists, so get the block")
			block_n = inode.content[i]
			block = get_block(inode.content[i])
		else
			--logprint(log_domain, function_name..": block doesnt exists, so create the block")
			--already commented--logprint(log_domain, function_name..": root's xattr=", {root_inode_xattr=root_inode.meta.xattr})
			root_inode.meta.xattr.greatest_block_n = root_inode.meta.xattr.greatest_block_n + 1
			--logprint(log_domain, function_name..": now greatest block number=", root_inode.meta.xattr.greatest_block_n)
			--TODO Concurrent writes can really fuck up the system cause im not writing on root at every time
			block_n = root_inode.meta.xattr.greatest_block_n
			block = ""
			table.insert(inode.content, block_n)
			--logprint(log_domain, function_name..": new inode with block =")
			--logprint(log_domain, table2str("inode", 0, inode))
		end
		--logprint(log_domain, function_name..": remaining_buf=", remaining_buf)
		--logprint(log_domain, function_name..": (#remaining_buf+block_offset)=", (#remaining_buf+block_offset))
		--logprint(log_domain, function_name..": block_size=", block_size)
		if (#remaining_buf+block_offset) > block_size then
			--logprint(log_domain, function_name..": more than block size")
			to_write_in_block = string.sub(remaining_buf, 1, (block_size - block_offset))
			remaining_buf = string.sub(remaining_buf, (block_size - block_offset)+1, -1)
		else
			--logprint(log_domain, function_name..": less than block size")
			to_write_in_block = remaining_buf
		end
		--logprint(log_domain, function_name..": block=", {block=block})
		--logprint(log_domain, function_name..": to_write_in_block=", to_write_in_block)
		--logprint(log_domain, function_name..": block_offset=", block_offset..", size of to_write_in_block=", #to_write_in_block)
		block = string.sub(block, 1, block_offset)..to_write_in_block..string.sub(block, (block_offset+#to_write_in_block+1)) --TODO CHECK IF THE +1 AT THE END IS OK
		--logprint(log_domain, function_name..": now block=", block)
		block_offset = 0
		table.insert(to_report_t, function_name..": before putting the block\telapsed_time="..(misc.time()-start_time).."\n")
		put_block(block_n, block)
		table.insert(to_report_t, function_name..": timestamp at the end of each cycle\telapsed_time="..(misc.time()-start_time).."\n")
	end

	if size_changed then
		inode.meta.size = offset+size
		put_inode(inode.meta.ino, inode)
		table.insert(to_report_t, function_name..": inode was written\telapsed_time="..(misc.time()-start_time).."\n")
		if blocks_created then
			put_inode(1, root_inode)
			table.insert(to_report_t, function_name..": root was written\telapsed_time="..(misc.time()-start_time).."\n")
		end
	end

	table.insert(to_report_t, function_name..": finished\telapsed_time="..(misc.time()-start_time).."\n")

	last_logprint(log_domain, table.concat(to_report_t))

	to_report_t = {}

	return #buf
end,

open=function(self, filename, mode) --NOTE: MAYBE OPEN DOESN'T DO ANYTHING BECAUSE OF THE SHARED NATURE OF THE FILESYSTEM; EVERY WRITE READ MUST BE ATOMIC AND
--LONG SESSIONS WITH THE LIKES OF OPEN HAVE NO SENSE.
--TODO: CHECK ABOUT MODE AND USER RIGHTS.
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "open"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename, {mode=mode})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "release"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename, {inode=inode})

	--[[
	inode.open = inode.open - 1
	logprint(log_domain, function_name..": for filename=", filename, {inode_open=inode.open})
	if inode.open < 1 then
		logprint(log_domain, function_name..": open < 1")
		if inode.changed then
			logprint(log_domain, function_name..": going to put")
			local ok_put_inode = put_inode(inode.ino, inode)
		end
		if inode.meta_changed then
			logprint(log_domain, function_name..": going to put")
			local ok_put_inode = put_inode(inode.ino, inode)
		end
		logprint(log_domain, function_name..": meta_changed = nil")
		inode.meta_changed = nil
		logprint(log_domain, function_name..": changed = nil")
		inode.changed = nil
	end
	--]]
	return 0
end,

fgetattr=function(self, filename, inode, ...) --TODO: CHECK IF fgetattr IS USEFUL, IT IS! TODO: CHECK WITH filename
	--logs entrance
	logprint("FILE_MISC_OP", "fgetattr: START, filename = ", filename)
	last_logprint("FILE_MISC_OP", table2str("inode", 0, inode))
	return get_attributes(filename)
end,

rmdir=function(self, filename)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "DIR_OP", "rmdir"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename)

	local inode_n = get_inode_n(filename)

	if inode_n then --TODO: WATCH OUT, I PUT THIS IF
		local dir, base = filename:splitfilename()

		--local inode = get_inode_from_filename(filename)
		--TODO: CHECK WHAT HAPPENS WHEN TRYING TO ERASE A NON-EMPTY DIR
		--logprint(log_domain, function_name..": got inode", {inode, inode})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "DIR_OP", "mkdir"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename, {mode=mode})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "create"
	--logs entrance
	logprint(log_domain, function_name..": START, filename")
	logprint(log_domain, function_name..": START, filename=", filename,{mode=mode,flag=flag})

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
	logprint("FILE_MISC_OP", "flush: START")
	logprint("FILE_MISC_OP", "flush: START, filename=", filename, {inode=inode})

	if inode.changed then
		--TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
	end
	return 0
end,

readlink=function(self, filename)
	--logs entrance
	logprint("LINK_OP", "readlink: START")
	logprint("LINK_OP", "readlink: START, filename=", filename)

	local inode = get_inode_from_filename(filename)
	if inode then
		return 0, inode.content[1]
	end
	return ENOENT
end,

symlink=function(self, from, to)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "LINK_OP", "symlink"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START",{from=from,to=to})

	local to_dir, to_base = to:splitfilename()
	local to_parent = get_inode_from_filename(to_dir)

	local root_inode = nil
	if to_parent.meta.ino == 1 then
		root_inode = to_parent
	else
		root_inode = get_inode(1)
	end

	logprint(log_domain, function_name..": root_inode retrieved",{root_inode=root_inode})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "MV_CP_OP", "rename"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, from=", from..", to=", to)

	if from == to then return 0 end

	local from_inode = get_inode_from_filename(from)
	
	if from_inode then

		logprint(log_domain, function_name..": entered in IF", {from_inode=from_inode})
		
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
		
		logprint(log_domain, function_name..": changes made", {to_parent=to_parent, from_parent=from_parent})
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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "LINK_OP", "link"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, from=", from..", to=", to)
   
	if from == to then return 0 end

	local from_inode = get_inode_from_filename(from)
	
	logprint(log_domain, function_name..": from_inode", {from_inode=from_inode})

	if from_inode then
		logprint(log_domain, function_name..": entered in IF")
		local to_dir, to_base = to:splitfilename()
		logprint(log_domain, function_name..": to_dir=", to_dir..", to_base=", to_base)
		local to_parent = get_inode_from_filename(to_dir)
		logprint(log_domain, function_name..": to_parent", {to_parent=to_parent})
		
		to_parent.content[to_base] = true
		logprint(log_domain, function_name..": added file in to_parent", {to_parent=to_parent})
		from_inode.meta.nlink = from_inode.meta.nlink + 1
		logprint(log_domain, function_name..": incremented nlink in from_inode", {from_inode=from_inode})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "LINK_OP", "unlink"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename)

	local inode = get_inode_from_filename(filename)
	
	if inode then
		local dir, base = filename:splitfilename()
		local parent = get_inode_from_filename(dir)

		logprint(log_domain, function_name..":", {parent=parent})
		
		parent.content[base] = nil

		logprint(log_domain, function_name..": link to file in parent removed", {parent=parent})

		inode.meta.nlink = inode.meta.nlink - 1

		logprint(log_domain, function_name..": now inode has less links =")
	logprint(log_domain, table2str("inode", 0, inode))
		
		--delete the file, because it's being unlinked
		local ok_delete_file = delete_file(filename)
		--put the parent ino, because the record of the file was deleted
		local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
		--if the inode has no more links
		if inode.meta.nlink == 0 then
			logprint(log_domain, function_name..": i have to delete the inode too")
			--delete the inode, since it's not linked anymore
			delete_inode(inode.meta.ino)
		else
			local ok_put_inode = put_inode(inode.meta.ino, inode)
		end
		return 0
	else
		logprint(log_domain, function_name..": ERROR no inode")
		return ENOENT
	end
end,

chown=function(self, filename, uid, gid)
	--logs entrance
	logprint("FILE_MISC_OP", "chown: START")
	logprint("FILE_MISC_OP", "chown: START, filename=", filename..", uid=", uid..", gid=", gid)

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
	logprint("FILE_MISC_OP", "chmod: START")
	logprint("FILE_MISC_OP", "chmod: START, filename=", filename, {mode=mode})

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
	logprint("FILE_MISC_OP", "utime: START")
	logprint("FILE_MISC_OP", "utime: START, filename=", filename, {atime=atime,mtime=mtime})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "ftruncate"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename, {size=size,inode=inode})
	
	local orig_size = inode.meta.size

	local block_idx = math.floor((size - 1) / block_size) + 1
	local rem_offset = size % block_size

	logprint(log_domain, function_name..": orig_size=", orig_size..", new_size=", size..", block_idx=", block_idx..", rem_offset=", rem_offset)
		
	for i=#inode.content, block_idx+1,-1 do
		logprint(log_domain, function_name..": about to remove block number inode.content["..i.."]=", inode.content[i])
		local ok_delete_from_db_block = delete_block(inode.content[i])
		table.remove(inode.content, i)
	end

	logprint(log_domain, function_name..": about to change block number inode.content["..block_idx.."]=", inode.content[block_idx])

	

	if rem_offset == 0 then
		logprint(log_domain, function_name..": last block must be empty, so we delete it")
		local ok_delete_from_db_block = delete_block(inode.content[block_idx])
		table.remove(inode.content, block_idx)
	else
		logprint(log_domain, function_name..": last block is not empty")
		local last_block = get_block(block_idx)
		logprint(log_domain, function_name..": it already has this=", last_block)
		local write_in_last_block = string.sub(last_block, 1, rem_offset)
		logprint(log_domain, function_name..": and we change to this=", write_in_last_block)
		local ok_put_block = put_block(inode.content[block_idx], write_in_last_block)
	end

	inode.meta.size = size

	logprint(log_domain, function_name..": about to write inode")

	local ok_put_inode = put_inode(inode.meta.ino, inode)

	return 0
end,

truncate=function(self, filename, size)
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "truncate"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename, {size=size})
	
	local inode = get_inode_from_filename(filename)
	
	logprint(log_domain, function_name..": inode was retrieved =")
	logprint(log_domain, table2str("inode", 0, inode))

	if inode then

		local orig_size = inode.meta.size

		local block_idx = math.floor((size - 1) / block_size) + 1
		local rem_offset = size % block_size

		logprint(log_domain, function_name..": orig_size=", orig_size..", new_size=", size..", block_idx=", block_idx..", rem_offset=", rem_offset)
		
		for i=#inode.content, block_idx+1,-1 do
			logprint(log_domain, function_name..": about to remove block number inode.content["..i.."]=", inode.content[i])
			local ok_delete_from_db_block = delete_block(inode.content[i])
			table.remove(inode.content, i)
		end

		if block_idx > 0 then
			logprint(log_domain, function_name..": about to change block number inode.content["..block_idx.."]=", inode.content[block_idx])

			if rem_offset == 0 then
				logprint(log_domain, function_name..": last block must be empty, so we delete it")
			
				local ok_delete_from_db_block = delete_block(inode.content[block_idx])
				table.remove(inode.content, block_idx)
			else
				logprint(log_domain, function_name..": last block is not empty")
				local last_block = get_block(block_idx)
				logprint(log_domain, function_name..": it already has this=", last_block)
				local write_in_last_block = string.sub(last_block, 1, rem_offset)
				logprint(log_domain, function_name..": and we change to this=", write_in_last_block)
				local ok_put_block = put_block(inode.content[block_idx], write_in_last_block)
			end
		end

		inode.meta.size = size

		logprint(log_domain, function_name..": about to write inode")

		local ok_put_inode = put_inode(inode.meta.ino, inode)

		return 0
	else
		return ENOENT
	end
end,

access=function(...)
	--logs entrance
	logprint("FILE_MISC_OP", "access: START")
	
	return 0
end,

fsync=function(self, filename, isdatasync, inode)
	--logs entrance
	logprint("FILE_MISC_OP", "fsync: START")
	logprint("FILE_MISC_OP", "fsync: START, filename=", filename, {isdatasync=isdatasync,inode=inode})
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
	logprint("FILE_MISC_OP", "fsyncdir: START")
	logprint("FILE_MISC_OP", "fsyncdir: START, filename=", filename, {isdatasync=isdatasync,inode=inode})

	return 0
end,
listxattr=function(self, filename, size)
	--logs entrance
	logprint("FILE_MISC_OP", "listxattr: START")
	logprint("FILE_MISC_OP", "listxattr: START, filename=", filename, {size=size})

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
	logprint("FILE_MISC_OP", "removexattr: START")
	logprint("FILE_MISC_OP", "removexattr: START, filename=", filename, {name=name})

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
	logprint("FILE_MISC_OP", "setxattr: START")
	logprint("FILE_MISC_OP", "setxattr: START, filename=", filename, {name=name,val=val,flags=flags})

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
	--for all the logprint functions: the log domain is "FILE_INODE_OP" and the function name is "put_block"
	local log_domain, function_name = "FILE_MISC_OP", "getxattr"
	--logs entrance
	logprint(log_domain, function_name..": START")
	logprint(log_domain, function_name..": START, filename=", filename, {name=name,size=size})

	local inode = get_inode_from_filename(filename)
	logprint(log_domain, function_name..": get_inode was successful =")
	logprint(log_domain, table2str("inode", 0, inode))
	if inode then
		logprint(log_domain, function_name..": retrieving xattr["..name.."]=", {inode_meta_xattr=inode.meta.xattr[name]})
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

logprint("MAIN_OP", "MAIN: before defining fuse_opt")

fuse_opt = { 'splayfuse', 'mnt', '-f', '-s', '-d', '-oallow_other'}

logprint("MAIN_OP", "MAIN: fuse_opt defined")

if select('#', ...) < 2 then
	print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
	os.exit(1)
end

logprint("MAIN_OP", "MAIN: going to execute fuse.main")

fuse.main(splayfuse, {...})
--events.run(function()
--	fuse.main(splayfuse, {"testsplayfuse","/home/unine/testsplayfuse/testsplayfuse/","-ouse_ino,big_writes","d"})
--end)
--profiler.stop()
