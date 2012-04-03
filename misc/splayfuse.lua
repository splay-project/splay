#!/usr/bin/env lua
--[[
    Memory FS in FUSE using the lua binding
    Copyright 2007 (C) gary ng <linux@garyng.com>

    This program can be distributed under the terms of the GNU LGPL.
]]

local fuse = require 'fuse'
local dbclient = require 'distdb-client'
local json = require'json'
local crypto = require'crypto'

local tjoin = table.concat
local tadd = table.insert
local floor = math.floor
local format = string.format
local now = os.time
local difftime = os.difftime

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
local mem_block_size = 4096
local blank_block=("0"):rep(mem_block_size)
local open_mode={'rb','wb','rb+'}
local log_domains = {
    DB_OP=true,
    FILE_INODE_OP=true,
    DIR_OP=true,
    LINK_OP=true,
    READ_WRITE_OP=true,
    FILE_MISC_OP=true,
    MV_CP_OP=true
}

local db_port = 13304

function reportlog(log_domain, function_name, args)
    if log_domains[log_domain] then
        local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")
        logfile1:write(now()..": "..function_name.."\n")
        logfile1:write(print_tablez("args", 0, args))
        logfile1:write("\n")
        logfile1:close()
    end
end

local function writedb(elem_type, unhashed_key, obj)
    local db_key = crypto.evp.digest("sha1", elem_type..":"..unhashed_key)
    reportlog("DB_OP", "writedb: about to write in distdb, unhashed_key="..unhashed_key..", db_key="..db_key,{obj=obj})
    --if it's not a inode
    if elem_type ~= "inode" or obj == "" then
        return send_put(db_port, "consistent", db_key, obj)
    end
    --if it's a inode, JSON-encode it first
    return send_put(db_port, "consistent", db_key, json.encode(obj))
end

local function readdb(elem_type, unhashed_key)
    local db_key = crypto.evp.digest("sha1", elem_type..":"..unhashed_key)
    reportlog("DB_OP", "readdb: about to read in distdb, unhashed_key="..unhashed_key..", db_key="..db_key,{})
    local ok_send_get, ret_send_get = send_get(db_port, "consistent", db_key)
    if not ok_send_get then
        return false
    end
    --if it's not a inode or there is a nil answer
    if elem_type ~= "inode" or (not ret_send_get) then
        reportlog("DB_OP", "readdb: returning without JSON",{ret_send_get=ret_send_get})
        --return directly the result
        return true, ret_send_get
    end
    --if it's a inode, JSON-decode it first
    return true, json.decode(ret_send_get)
end

function string:splitfilename() 
    local dir,file = self:match("(.-)([^:/\\]*)$")
    local dirmatch = dir:match("(.-)[/\\]?$")
    if dir == "/" then
        return dir, file
    else
        return dir:match("(.-)[/\\]?$"), file
    end
end


--TODO: IS THIS USED?
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

local function decode_acl(s)

    reportlog("FILE_INODE_OP", "decode_acl: ENTERED for s="..s, {})

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

local function clear_buffer(inode,from,to)
    --logs entrance
    reportlog("FILE_INODE_OP", "clear_buffer: ENTERED for inode="..inode..", from="..from..", to="..to, {})

    for i = from, to do inode.content[i] = nil end

    collectgarbage("collect")
end

local function mk_mode(owner, group, world, sticky)

    reportlog("FILE_INODE_OP", "mk_mode: ENTERED for owner="..owner..", group="..group..", world="..world, {sticky=sticky})

    sticky = sticky or 0
    local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID
    reportlog("_OP", "mk_mode returns result_mode="..result_mode, {})
    return result_mode
end

--gets a inode element from the db
local function get_inode(inode_n)
    --logs entrance
    reportlog("FILE_INODE_OP", "get_inode: ENTERED for inode_n=", {inode_n=inode_n})
    
    if type(inode_n) ~= "number" then
        reportlog("FILE_INODE_OP", "get_inode: ERROR, inode_n not a number", {})
        return nil
    end

    local ok_readdb_inode, inode = readdb("inode", inode_n)

    reportlog("FILE_INODE_OP", "get_inode: readdb returned", {inode=inode})

    if not ok_readdb_inode then
        reportlog("FILE_INODE_OP", "get_inode: ERROR, readdb of inode was not OK", {})
        return nil
    end

    return inode
end

--gets a inode number from the db, by identifying it with the filename
local function get_inode_n(filename)
    --logs entrance
    reportlog("FILE_INODE_OP", "get_inode_n: ENTERED for filename="..filename, {})

    local ok_readdb_file, inode_n = readdb("file", filename)

    if not ok_readdb_file then
        reportlog("FILE_INODE_OP", "get_inode_n: ERROR, readdb of file was not OK", {})
        return nil
    end
    return inode_n
end

--gets a inode element from the db, by identifying it with the filename
local function get_inode_from_filename(filename)
    --logs entrance
    reportlog("FILE_INODE_OP", "get_inode_from_filename: ENTERED for filename="..filename, {})

    local inode_n = tonumber(get_inode_n(filename)) --TODO: CHECK IF TONUMBER IS NECESSARY

    return get_inode(inode_n)
end

--puts a inode element into the db
local function put_inode(inode_n, inode)
    --logs entrance
    reportlog("FILE_INODE_OP", "put_inode: ENTERED for inode_n="..inode_n, {inode=inode})
    
    if type(inode_n) ~= "number" then
        reportlog("FILE_INODE_OP", "put_inode: ERROR, inode_n not a number", {})
        return nil
    end

    if type(inode) ~= "table" then
        reportlog("FILE_INODE_OP", "put_inode: ERROR, inode not a table", {})
        return nil
    end    

    local ok_writedb_inode = writedb("inode", inode_n, inode)

    if not ok_writedb_inode then
        reportlog("FILE_INODE_OP", "put_inode: ERROR, writedb of inode was not OK", {})
        return nil
    end

    return true
end

--puts a file element into the db
local function put_file(filename, inode_n)
    
    if type(filename) ~= "string" then
        reportlog("FILE_INODE_OP", "put_file: ERROR, filename not a string", {})
        return nil
    end

    --logs entrance
    reportlog("FILE_INODE_OP", "put_file: ENTERED for filename="..filename..", inode_n="..inode_n, {})
    
    if type(inode_n) ~= "number" then
        reportlog("FILE_INODE_OP", "put_file: ERROR, inode_n not a number", {})
        return nil
    end

    local ok_writedb_file = writedb("file", filename, inode_n)

    if not ok_writedb_file then
        reportlog("FILE_INODE_OP", "put_file: ERROR, writedb of inode was not OK", {})
        return nil
    end

    return true
end

local function delete_inode(inode_n, inode)
--TODOS: WEIRD LATENCY IN DELETE_LOCAL
--DELETE AS PUT "" IS UGLY, BETTER TO CREATE A DIFF WEB SERVICE CALL
--I THINK THE INODE DOES NOT GET DELETED.
    --logs entrance
    reportlog("FILE_INODE_OP", "delete_inode: ENTERED for inode_n="..inode_n, {inode=inode})
    
    if type(inode_n) ~= "number" then
        reportlog("FILE_INODE_OP", "delete_inode: ERROR, inode_n not a number", {})
        return nil
    end

    if type(inode) ~= "table" then
        reportlog("FILE_INODE_OP", "delete_inode: ERROR, inode not a table", {})
        return nil
    end

    --[[
    for i,v in ipairs(inode.content) do
        writedb("block", v, nil) --TODO: NOT CHECKING IF SUCCESSFUL
    end
    --]]

    
    local ok_writedb_inode = writedb("inode", inode_n, "")

    if not ok_writedb_inode then
        reportlog("_OP", "delete_inode: ERROR, writedb of inode was not OK", {})
        return nil
    end
    
    return true
end

local function delete_dir_inode(inode_n)
    --logs entrance
    reportlog("FILE_INODE_OP", "delete_dir_inode: ENTERED for inode_n="..inode_n, {})
    
    if type(inode_n) ~= "number" then
        reportlog("FILE_INODE_OP", "delete_inode: ERROR, inode_n not a number", {})
        return nil
    end

    
    local ok_writedb_inode = writedb("inode", inode_n, "")

    if not ok_writedb_inode then
        reportlog("_OP", "delete_dir_inode: ERROR, writedb of inode was not OK", {})
        return nil
    end

    return true
end

local function delete_file(filename)

    if type(filename) ~= "string" then
        reportlog("FILE_INODE_OP", "delete_file: ERROR, filename not a string", {})
        return nil
    end

    --logs entrance
    reportlog("FILE_INODE_OP", "delete_file: ENTERED for filename="..filename, {inode=inode})
    
    if type(inode) ~= "table" then
        reportlog("FILE_INODE_OP", "delete_inode: ERROR, inode not a table", {})
        return nil
    end

    local ok_writedb_file = writedb("file", filename, "")

    if not ok_writedb_file then
        reportlog("FILE_INODE_OP", "delete_file: ERROR, writedb of inode was not OK", {})
        return nil
    end

    return true
end


local uid,gid,pid,puid,pgid = fuse.context()

local root_inode = get_inode(1)

--I THINK ROOT_INODE IS NOT EVEN NEEDED, IT WAS USED FOR dir_walk
if not root_inode then

    reportlog("FILE_INODE_OP", "creating root",{})
    
    root_inode = {
        meta = {
            ino = 1,
            xattr ={greatest_inode_n=1},
            mode  = mk_mode(7,5,5) + S_IFDIR,
            nlink = 2, uid = puid, gid = pgid, size = 0, atime = now(), mtime = now(), ctime = now()
        },
        content = {}
    } -- JV: ADDED FOR REPLACEMENT WITH DISTDB

    put_file("/", 1)
    put_inode(1, root_inode)
end

local function unlink_node(inode, filename) --PA DESPUES CREO QUE ES ERASE FILE
    --logs entrance
    reportlog("FILE_MISC_OP", "unlink_node: ENTERED", {inode=inode, filename=filename})

    local meta = inode.meta
    meta.nlink = meta.nlink - 1 - (is_dir(meta.mode) and 1 or 0)
    if meta.nlink == 0 then
        inode.content = nil
        inode.meta = nil
    else
        --if (inode.open or 0) < 1 then
            --mnode.flush_node(inode, filename, true)
            --TODO: WHAT INSTEAD OF THAT?
        --else inode.meta_changed = true end
    end
end

local memfs = {

pulse = function()
    --logs entrance
    reportlog("FILE_MISC_OP", "pulse: ENTERED", {})

    print "periodic pulse"
end,

getattr = function(self, filename)
    --logs entrance
    reportlog("FILE_MISC_OP", "getattr: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    reportlog("FILE_MISC_OP", "getattr: for filename="..filename.." get_inode_from_filename returned=",{inode=inode})
    if not inode then return ENOENT end
    local x = inode.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

opendir = function(self, filename)
    --logs entrance
    reportlog("DIR_OP", "opendir: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    reportlog("DIR_OP", "opendir: for filename="..filename.." get_inode_from_filename returned",{inode=inode})
    if not inode then return ENOENT end
    return 0, inode
end,

readdir = function(self, filename, offset, inode)
    --logs entrance
    reportlog("DIR_OP", "readdir: ENTERED for filename="..filename..", offset="..offset, {inode=inode})

    local out={'.','..'}
    for k,v in pairs(inode.content) do
        if type(k) == "string" then out[#out+1] = k end
    end
    return 0, out
end,

releasedir = function(self, filename, inode)
    --logs entrance
    reportlog("DIR_OP", "releasedir: ENTERED for filename="..filename, {inode=inode})

    return 0
end,

mknod = function(self, filename, mode, rdev) --JV: NOT SURE IF TO CHANGE OR NOT....!!!
    --logs entrance
    reportlog("FILE_MISC_OP", "mknod: ENTERED for filename="..filename, {mode=mode,rdev=rdev})

    local inode = get_inode_from_filename(filename)
    
    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = get_inode(1)
        root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
        local greatest_ino = root_inode.meta.xattr.greatest_inode_n
        
        local uid, gid, pid = fuse.context()
        
        inode = {
            meta = {
                ino = greatest_ino,
                mode = mode,
                dev = rdev, 
                nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()
            },
            content = {""} --TODO: MAYBE THIS IS EMPTY
        }
        reportlog("FILE_MISC_OP", "mknod: what is parent_parent?", {parent_parent=parent.parent})
        parent.content[base]=true
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        local ok_put_inode = put_inode(greatest_ino, inode)
        local ok_put_file = put_file(filename, greatest_ino)
        local ok_put_root_inode = put_inode(1, root_inode)
        return 0, o
    end
end,

read = function(self, filename, size, offset, inode)
    --logs entrance
    reportlog("READ_WRITE_OP", "read: ENTERED for filename="..filename..", size="..size..", offset="..offset,{inode=inode})

    --local block = floor(offset/mem_block_size) --JV: NOT NEEDED FOR THE MOMENT
    --local o = offset%mem_block_size --JV: NOT NEEDED FOR THE MOMENT
    --local data={} --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    
    --[[
    if o == 0 and size % mem_block_size == 0 then
        for i=block, block + floor(size/mem_block_size) - 1 do
            data[#data+1]=inode.content[i] or blank_block
        end
    else
        while size > 0 do
            local x = inode.content[block] or blank_block
            local b_size = mem_block_size - o 
            if b_size > size then b_size = size end
            data[#data+1]=x:sub(o+1, b_size)
            o = 0
            size = size - b_size
            block = block + 1
        end
    end --JV: NOT NEEDED FOR THE MOMENT
    --]]

    reportlog("READ_WRITE_OP", "read: for filename="..filename.." the full content of inode:",{inode_content=inode.content})

    --if size + offset < string.len(inode.content[1]) then -- JV: CREO QUE ESTO NO SE USA
    local data = string.sub(inode.content[1], offset, (offset+size)) --JV: WATCH OUT WITH THE LOCAL STUFF... WHEN PUT INSIDE THE IF
    --end --JV: CORRESPONDS TO THE IF ABOVE

    reportlog("READ_WRITE_OP", "read: for filename="..filename.." returns",{data=data})

    --return 0, tjoin(data,"") --JV: REMOVED FOR REPLACEMENT WITH DISTDB; data IS ALREADY A STRING
    return 0, data --JV: ADDED FOR REPLACEMENT WITH DISTDB
end,

write = function(self, filename, buf, offset, inode)
    --logs entrance
    reportlog("READ_WRITE_OP", "write: ENTERED for filename="..filename, {buf=buf,offset=offset,inode=inode})

    --inode.changed = true
    local size = #buf
    
    --[[
    local o = offset % mem_block_size
    local block = floor(offset / mem_block_size)
    if o == 0 and size % mem_block_size == 0 then
        local start = 0
        for i=block, block + floor(size/mem_block_size) - 1 do
            inode.content[i] = buf:sub(start + 1, start + mem_block_size)
            start = start + mem_block_size
        end
    else
        local start = 0
        while size > 0 do
            local x = inode.content[block] or blank_block
            local b_size = mem_block_size - o 
            if b_size > size then b_size = size end
            inode.content[block] = tjoin({x:sub(1, o), buf:sub(start+1, start + b_size), x:sub(o + 1 + b_size)},"")
            o = 0
            size = size - b_size
            block = block + 1
        end
    end --JV: NOT NEEDED FOR THE MOMENT
    --]]
    reportlog("READ_WRITE_OP", "write: CHECKPOINT1",{})
    if not inode.content[1] then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        inode.content[1] = "" --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("READ_WRITE_OP", "write: CHECKPOINT1a",{})
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    reportlog("READ_WRITE_OP", "write: CHECKPOINT2",{})
    local old_content = inode.content[1] --JV: ADDED FOR REPLACEMENT WITH DISTDB
    local old_size = string.len(inode.content[1])
    if (offset+size) < old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        inode.content[1] = string.sub(old_content, 1, offset)..buf..string.sub(old_content, (offset+size+1), -1) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("READ_WRITE_OP", "write: CHECKPOINT3a",{})
    else --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("READ_WRITE_OP", "write: CHECKPOINT3b",{})
        inode.content[1] = string.sub(old_content, 1, offset)..buf --JV: ADDED FOR REPLACEMENT WITH DISTDB
        if (offset+size) > old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
            reportlog("READ_WRITE_OP", "write: CHECKPOINT3c",{})
            inode.meta.size = offset+size --JV: ADDED FOR REPLACEMENT WITH DISTDB
            --inode.meta_changed = true --JV: ADDED FOR REPLACEMENT WITH DISTDB
        end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB

    --local eof = offset + #buf --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    --if eof > inode.meta.size then inode.meta.size = eof ; inode.meta_changed = true end --JV: REMOVED FOR REPLACEMENT WITH DISTDB

    local ok_put_inode = put_inode(inode.meta.ino, inode) --JV: ADDED FOR REPLACEMENT WITH DISTDB

    return #buf
end,

open = function(self, filename, mode) --NOTE: MAYBE OPEN DOESN'T DO ANYTHING BECAUSE OF THE SHARED NATURE OF THE FILESYSTEM; EVERY WRITE READ MUST BE ATOMIC AND
--LONG SESSIONS WITH THE LIKES OF OPEN HAVE NO SENSE.
--TODO: CHECK ABOUT MODE AND USER RIGHTS.
    --logs entrance
    reportlog("FILE_MISC_OP", "open: ENTERED for filename="..filename, {mode=mode})

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

release = function(self, filename, inode) --NOTE: RELEASE DOESNT SEEM TO MAKE MUCH SENSE
    --logs entrance
    reportlog("FILE_MISC_OP", "release: ENTERED for filename="..filename, {inode=inode})

    --[[
    inode.open = inode.open - 1
    reportlog("_OP", "release: for filename="..filename, {inode_open=inode.open})
    if inode.open < 1 then
        reportlog("_OP", "release: open < 1", {})
        if inode.changed then
            reportlog("_OP", "release: gonna put", {})
            local ok_put_inode = put_inode(inode.ino, inode)
        end
        if inode.meta_changed then
            reportlog("_OP", "release: gonna put", {})
            local ok_put_inode = put_inode(inode.ino, inode)
        end
        reportlog("_OP", "release: meta_changed = nil", {})
        inode.meta_changed = nil
        reportlog("_OP", "release: changed = nil", {})
        inode.changed = nil
    end
    --]]
    return 0
end,

fgetattr = function(self, filename, obj, ...) --TODO: CHECK IF fgetattr IS USEFUL, IT IS! TODO: CHECK WITH filename
    --logs entrance
    reportlog("FILE_MISC_OP", "fgetattr: ENTERED for filename="..filename, {obj=obj})

    local x = obj.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

rmdir = function(self, filename)
    --logs entrance
    reportlog("DIR_OP", "rmdir: ENTERED for filename="..filename, {})

    local inode_n = get_inode_n(filename)

    if inode_n then --TODO: WATCH OUT, I PUT THIS IF
        local dir, base = filename:splitfilename()

        --local inode = get_inode_from_filename(filename)
        --TODO: CHECK WHAT HAPPENS WHEN TRYING TO ERASE A NON-EMPTY DIR
        --reportlog("_OP", "rmdir: got inode", {inode, inode})

        local parent = get_inode_from_filename(dir)
        parent.content[base] = nil
        parent.meta.nlink = parent.meta.nlink - 1

        delete_file(filename)
        delete_dir_inode(inode_n)
        put_inode(parent.ino, parent)
    end
    return 0
end,

mkdir = function(self, filename, mode, ...) --TODO: CHECK WHAT HAPPENS WHEN TRYING TO MKDIR A DIR THAT EXISTS
--TODO: MERGE THESE CODES (MKDIR, MKNODE, CREATE) ON 1 FUNCTION
    --logs entrance
    reportlog("DIR_OP", "mkdir: ENTERED for filename="..filename, {mode=mode})

    local inode = get_inode_from_filename(filename)

    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = get_inode(1)
        root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
        local greatest_ino = root_inode.meta.xattr.greatest_inode_n
        
        local uid, gid, pid = fuse.context()
        
        inode = {
            meta = {
                mode = set_bits(mode,S_IFDIR),
                ino = greatest_ino, 
                dev = 0, --TODO: CHECK IF USEFUL
                nlink = 2, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now() --TODO: CHECK IF SIZE IS NOT MAX_BLOCK_SIZE
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

create = function(self, filename, mode, flag, ...)
    --logs entrance
    reportlog("FILE_MISC_OP", "create: ENTERED for filename="..filename,{mode=mode,flag=flag})

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
                mode  = set_bits(mode, S_IFREG),
                ino = greatest_ino, 
                dev = 0, 
                nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()
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

flush = function(self, filename, obj)
    --logs entrance
    reportlog("FILE_MISC_OP", "flush: ENTERED for filename="..filename, {obj=obj})

    if obj.changed then
        --TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
    end
    return 0
end,

readlink = function(self, filename)
    --logs entrance
    reportlog("LINK_OP", "readlink: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    if inode then
        return 0, inode.content[1]
    end
    return ENOENT
end,

symlink = function(self, from, to)
    --logs entrance
    reportlog("LINK_OP", "symlink: ENTERED",{from=from,to=to})

    local to_dir, to_base = to:splitfilename()
    local to_parent = get_inode_from_filename(to_dir)

    local root_inode = nil
    if to_parent.meta.ino == 1 then
        root_inode = to_parent
    else
        root_inode = get_inode(1)
    end

    reportlog("LINK_OP", "symlink: root_inode retrieved",{root_inode=root_inode})

    root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
    local greatest_ino = root_inode.meta.xattr.greatest_inode_n

    local uid, gid, pid = fuse.context()

    local to_inode = {
        meta = {
            mode= S_IFLNK+mk_mode(7,7,7),
            ino = greatest_ino, 
            dev = 0, 
            nlink = 1, uid = uid, gid = gid, size = string.len(from), atime = now(), mtime = now(), ctime = now()
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
    return 0
end,

rename = function(self, from, to)
    --logs entrance
    reportlog("MV_CP_OP", "rename: ENTERED, from="..from..", to="..to, {})

    if from == to then return 0 end

    local from_inode = get_inode_from_filename(from)
    
    if from_inode then

        reportlog("MV_CP_OP", "rename: entered in IF", {from_inode=from_inode})
        
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
        
        reportlog("MV_CP_OP", "rename: changes made", {to_parent=to_parent, from_parent=from_parent})
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
            local ok_writedb_inode = writedb(to, inode) --JV: ADDED FOR REPLACEMENT WITH DISTDB
            --TODO: WTF DO I DO HERE?
        else
            inode.meta_changed = true
        end
        --]]
        return 0
    end
end,

link = function(self, from, to, ...)
    --logs entrance
    reportlog("LINK_OP", "link: ENTERED, from="..from..", to="..to, {})
   
    if from == to then return 0 end

    local from_inode = get_inode_from_filename(from)
    
    reportlog("LINK_OP", "link: from_inode", {from_inode=from_inode})

    if from_inode then
        reportlog("LINK_OP", "link: entered in IF", {})
        local to_dir, to_base = to:splitfilename()
        reportlog("LINK_OP", "link: to_dir="..to_dir..", to_base="..to_base, {})
        local to_parent = get_inode_from_filename(to_dir)
        reportlog("LINK_OP", "link: to_parent", {to_parent=to_parent})
        
        to_parent.content[to_base] = true
        reportlog("LINK_OP", "link: added file in to_parent", {to_parent=to_parent})
        from_inode.meta.nlink = from_inode.meta.nlink + 1
        reportlog("LINK_OP", "link: incremented nlink in from_inode", {from_inode=from_inode})

        --put the to_parent's inode, because the contents changed
        local ok_put_to_parent = put_inode(to_parent.meta.ino, to_parent)
        --put the inode, because nlink was incremented
        local ok_put_inode = put_inode(from_inode.meta.ino, from_inode)
        --put the to_file, because it's new
        local ok_put_file = put_file(to, from_inode.meta.ino)
        return 0
    end
end,

unlink = function(self, filename, ...)
    --logs entrance
    reportlog("LINK_OP", "unlink: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    
    if inode then
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        parent.content[base] = nil
        inode.meta.nlink = inode.meta.nlink - 1
        
        --delete the file, because it's being unlinked
        local ok_delete_file = delete_file(filename, inode)
        --put the parent ino, because the record of the file was deleted
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        --if the inode has no more links
        if inode.meta.nlink == 0 then
            --delete the inode, since it's not linked anymore
            delete_inode(inode.meta.ino, inode)
        else
            local ok_put_inode = put_inode(inode.meta.ino, inode)
        end
        return 0
    else
        reportlog("_OP", "unlink: ERROR no inode", {})
        return ENOENT
    end
end,

chown = function(self, filename, uid, gid)
    --logs entrance
    reportlog("FILE_MISC_OP", "chown: ENTERED for filename="..filename..", uid="..uid..", gid="..gid, {})

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
    reportlog("FILE_MISC_OP", "chmod: ENTERED for filename="..filename, {mode=mode})

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
    reportlog("FILE_MISC_OP", "utime: ENTERED for filename="..filename, {atime=atime,mtime=mtime})

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
ftruncate = function(self, filename, size, obj)
    --logs entrance
    reportlog("FILE_MISC_OP", "ftruncate: ENTERED for filename="..filename, {size=size,obj=obj})
    --TODO: PA DESPUES
    --local old_size = obj.meta.size
    --obj.meta.size = size
    --clear_buffer(obj, floor(size/mem_block_size), floor(old_size/mem_block_size))
    return 0
end,

truncate = function(self, filename, size)
    --logs entrance
    reportlog("FILE_MISC_OP", "truncate: ENTERED for filename="..filename, {size=size})
    --TODO: PA DESPUES
    --[[
    local inode,parent = get_inode_from_filename(filename)
    if inode then 
        local old_size = inode.meta.size
        inode.meta.size = size
        clear_buffer(inode, floor(size/mem_block_size), floor(old_size/mem_block_size))
        if (inode.open or 0) < 1 then mnode.flush_node(inode, filename, true) 
        else inode.meta_changed = true end
        return 0
    else
        return ENOENT
    end
    --]]
    return 0
end,
access = function(...)
    --logs entrance
    reportlog("FILE_MISC_OP", "access: ENTERED",{})

    return 0
end,
fsync = function(self, filename, isdatasync, obj)
    --logs entrance
    reportlog("FILE_MISC_OP", "fsync: ENTERED for filename="..filename, {isdatasync=isdatasync,obj=obj})
    --TODO: PA DESPUES
    --[[
    mnode.flush_node(obj, filename, false) 
    if isdatasync and obj.changed then 
        mnode.flush_data(obj.content, obj, filename) 
    end
    --]]
    return 0
end,
fsyncdir = function(self, filename, isdatasync, obj)
    --logs entrance
    reportlog("FILE_MISC_OP", "fsyncdir: ENTERED for filename="..filename, {isdatasync=isdatasync,obj=obj})

    return 0
end,
listxattr = function(self, filename, size)
    --logs entrance
    reportlog("FILE_MISC_OP", "listxattr: ENTERED for filename="..filename, {size=size})

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
    reportlog("FILE_MISC_OP", "removexattr: ENTERED for filename="..filename, {name=name})

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
    reportlog("FILE_MISC_OP", "setxattr: ENTERED for filename="..filename, {name=name,val=val,flags=flags})

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
    --logs entrance
    reportlog("FILE_MISC_OP", "getxattr: ENTERED for filename="..filename, {name=name,size=size})

    local inode = get_inode_from_filename(filename)
    if inode then
        return 0, inode.meta.xattr[name] or "" --not found is empty string
    else
        return ENOENT
    end
end,

statfs = function(self,filename)
    local inode,parent = get_inode_from_filename(filename)
    local o = {bs=1024,blocks=64,bfree=48,bavail=48,bfiles=16,bffree=16}
    return 0, o.bs, o.blocks, o.bfree, o.bavail, o.bfiles, o.bffree
end
}

fuse_opt = { 'memfs', 'mnt', '-f', '-s', '-oallow_other'}

if select('#', ...) < 2 then
    print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
    os.exit(1)
end

fuse.main(memfs, {...})
