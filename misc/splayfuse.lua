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

local db_port = 13271

function reportlog(function_name, args)
    local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")
    logfile1:write(now()..": "..function_name.."\n")
    logfile1:write(print_tablez("args", 0, args))
    logfile1:write("\n")
    logfile1:close()
end

local function writedb(elem_type, unhashed_key, obj)
    local db_key = crypto.evp.digest("sha1", elem_type..":"..unhashed_key)
    reportlog("writedb: about to write in distdb, unhashed_key="..unhashed_key..", db_key="..db_key,{obj=obj})
    --if it's not a inode
    if elem_type ~= "inode" then
        return send_put(db_port, "consistent", db_key, obj)
    end
    --if it's a inode, JSON-encode it first
    return send_put(db_port, "consistent", db_key, json.encode(obj))
end

local function readdb(elem_type, unhashed_key)
    local db_key = crypto.evp.digest("sha1", elem_type..":"..unhashed_key)
    reportlog("readdb: about to read in distdb, unhashed_key="..unhashed_key..", db_key="..db_key,{})
    local ok_send_get, ret_send_get = send_get(db_port, "consistent", db_key)
    if not ok_send_get then
        return false
    end
    --if it's not a inode
    if elem_type ~= "inode" then
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

    reportlog("decode_acl: ENTERED for s="..s, {})

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
    reportlog("clear_buffer: ENTERED for inode="..inode..", from="..from..", to="..to})

    for i = from, to do inode.content[i] = nil end

    collectgarbage("collect")
end

local function mk_mode(owner, group, world, sticky)

    reportlog("mk_mode: ENTERED for owner="..owner..", group="..group..", world="..world..", sticky="..sticky})

    sticky = sticky or 0
    local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID
    reportlog("mk_mode returns result_mode="..result_mode, {})
    return result_mode
end

--gets a inode element from the db
local function get_inode(inode_n)
    --logs entrance
    reportlog("get_inode: ENTERED for inode_n="..inode_n, {})
    
    if type(inode_n) ~= "number" then
        reportlog("get_inode: ERROR, inode_n not a number")
        return nil
    end

    local ok_readdb_inode, inode = readdb("inode", inode_n)

    if not ok_readdb_inode then
        reportlog("get_inode: ERROR, readdb of inode was not OK")
        return nil
    end

    return inode
end

--gets a inode number from the db, by identifying it with the filename
local function get_inode_n(filename)
    --logs entrance
    reportlog("get_inode_n: ENTERED for filename="..filename, {})

    local ok_readdb_file, inode_n = readdb("file", filename)

    if not ok_readdb_file then
        reportlog("get_inode_n: ERROR, readdb of file was not OK")
        return nil
    end
    return inode_n
end

--gets a inode element from the db, by identifying it with the filename
local function get_inode_from_filename(filename)
    --logs entrance
    reportlog("get_inode_from_filename: ENTERED for filename="..filename, {})

    local inode_n = tonumber(get_inode_n(filename)) --TODO: CHECK IF TONUMBER IS NECESSARY

    return get_inode(inode_n)
end

--puts a inode element into the db
local function put_inode(inode_n, inode)
    --logs entrance
    reportlog("put_inode: ENTERED for inode_n="..inode_n, {inode=inode})
    
    if type(inode_n) ~= "number" then
        reportlog("put_inode: ERROR, inode_n not a number")
        return nil
    end

    if type(inode) ~= "table" then
        reportlog("put_inode: ERROR, inode not a table")
        return nil
    end    

    local ok_writedb_inode = writedb("inode", inode_n, json.encode(inode))

    if not ok_writedb_inode then
        reportlog("put_inode: ERROR, writedb of inode was not OK")
        return nil
    end

    return true
end

--puts a file element into the db
local function put_file(filename, inode_n)
    
    if type(filename) ~= "string" then
        reportlog("put_file: ERROR, filename not a string")
        return nil
    end

    --logs entrance
    reportlog("put_file: ENTERED for filename="..filename..", inode_n="..inode_n, {})
    
    if type(inode_n) ~= "number" then
        reportlog("put_file: ERROR, inode_n not a number")
        return nil
    end

    local ok_writedb_file = writedb("file", filename, inode_n)

    if not ok_writedb_file then
        reportlog("put_file: ERROR, writedb of inode was not OK")
        return nil
    end

    return true
end

local function delete_inode(inode_n, inode)
    --logs entrance
    reportlog("delete_inode: ENTERED for inode_n="..inode_n, {inode=inode})
    
    if type(inode_n) ~= "number" then
        reportlog("delete_inode: ERROR, inode_n not a number")
        return nil
    end

    if type(inode) ~= "table" then
        reportlog("delete_inode: ERROR, inode not a table")
        return nil
    end

    --[[
    for i,v in ipairs(inode.content) do
        writedb("block", v, nil) --TODO: NOT CHECKING IF SUCCESSFUL
    end
    --]]

    --[[
    local ok_writedb_inode = writedb("inode", inode_n, nil)

    if not ok_writedb_inode then
        reportlog("delete_inode: ERROR, writedb of inode was not OK")
        return nil
    end
    --]]
    return true
end

local function delete_dir_inode(inode_n)
    --logs entrance
    reportlog("delete_dir_inode: ENTERED for inode_n="..inode_n, {})
    
    if type(inode_n) ~= "number" then
        reportlog("delete_inode: ERROR, inode_n not a number")
        return nil
    end

    --[[
    local ok_writedb_inode = writedb("inode", inode_n, nil)

    if not ok_writedb_inode then
        reportlog("delete_dir_inode: ERROR, writedb of inode was not OK")
        return nil
    end
    --]]
    return true
end

local function delete_file(filename)

    if type(filename) ~= "string" then
        reportlog("delete_file: ERROR, filename not a string")
        return nil
    end

    --logs entrance
    reportlog("delete_file: ENTERED for filename="..filename, {inode=inode})
    
    if type(inode) ~= "table" then
        reportlog("delete_inode: ERROR, inode not a table")
        return nil
    end

    local ok_writedb_file = writedb("file", filename, nil)

    if not ok_writedb_file then
        reportlog("delete_file: ERROR, writedb of inode was not OK")
        return nil
    end

    return true
end


local uid,gid,pid,puid,pgid = fuse.context()

local root_inode = get_inode(0)

--I THINK ROOT_INODE IS NOT EVEN NEEDED, IT WAS USED FOR dir_walk
if not root_inode then

    reportlog("creating root",{})
    
    root_inode = {
        meta = {
            ino = 0,
            xattr ={greatest_inode_n=0},
            mode  = mk_mode(7,5,5) + S_IFDIR,
            nlink = 2, uid = puid, gid = pgid, size = 0, atime = now(), mtime = now(), ctime = now()
        },
        content = {}
    } -- JV: ADDED FOR REPLACEMENT WITH DISTDB

    put_inode(0, root_inode)
end

local function unlink_node(inode, filename) --PA DESPUES CREO QUE ES ERASE FILE
    --logs entrance
    reportlog("unlink_node: ENTERED", {inode=inode, filename=filename})

    local meta = inode.meta
    meta.nlink = meta.nlink - 1 - (is_dir(meta.mode) and 1 or 0)
    if meta.nlink == 0 then
        inode.content = nil
        inode.meta = nil
    else
        if (inode.open or 0) < 1 then
            --mnode.flush_node(inode, filename, true)
            --TODO: WHAT INSTEAD OF THAT?
        else inode.meta_changed = true end
    end
end

local memfs = {

pulse = function()
    --logs entrance
    reportlog("pulse: ENTERED", {})

    print "periodic pulse"
end,

getattr = function(self, filename)
    --logs entrance
    reportlog("getattr: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    reportlog("getattr: for filename="..filename.." get_inode_from_filename returned=",{inode=inode})
    if not inode then return ENOENT end
    local x = inode.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

opendir = function(self, filename)
    --logs entrance
    reportlog("opendir: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    reportlog("opendir: for filename="..filename.." get_inode_from_filename returned",{inode=inode})
    if not inode then return ENOENT end
    return 0, inode
end,

readdir = function(self, filename, offset, inode)
    --logs entrance
    reportlog("readdir: ENTERED for filename="..filename..", offset="..offset, {inode=inode})

    local out={'.','..'}
    for k,v in pairs(inode.content) do
        if type(k) == "string" then out[#out+1] = k end
    end
    return 0, out
end,

releasedir = function(self, filename, inode)
    --logs entrance
    reportlog("releasedir: ENTERED for filename="..filename, {inode=inode})

    return 0
end,

mknod = function(self, filename, mode, rdev) --JV: NOT SURE IF TO CHANGE OR NOT....!!!
    --logs entrance
    reportlog("mknod: ENTERED for filename="..filename, {mode=mode,rdev=rdev})

    local inode = get_inode_from_filename(filename)
    
    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = get_inode(0)
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
        reportlog("mknod: what is parent_parent?", {parent_parent=parent.parent})
        parent.content[base]=true
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        local ok_put_inode = put_inode(greatest_ino, inode)
        local ok_put_file = put_file(filename, greatest_ino)
        local ok_put_root_inode = put_inode(0, root_inode)
        return 0, o
    end
end,

read = function(self, filename, size, offset, inode)
    --logs entrance
    reportlog("read: ENTERED for filename="..filename..", size="..size..", offset="..offset,{inode=inode})

    --local block = floor(offset/mem_block_size) --JV: NOT NEEDED FOR THE MOMENT
    --local o = offset%mem_block_size --JV: NOT NEEDED FOR THE MOMENT
    --local data={} --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    
    --[[
    if o == 0 and size % mem_block_size == 0 then
        for i=block, block + floor(size/mem_block_size) - 1 do
            data[#data+1]=obj.content[i] or blank_block
        end
    else
        while size > 0 do
            local x = obj.content[block] or blank_block
            local b_size = mem_block_size - o 
            if b_size > size then b_size = size end
            data[#data+1]=x:sub(o+1, b_size)
            o = 0
            size = size - b_size
            block = block + 1
        end
    end --JV: NOT NEEDED FOR THE MOMENT
    --]]

    reportlog("read: for filename="..filename.." the full content of obj:",{obj_content=obj.content})

    --if size + offset < string.len(obj.content[1]) then -- JV: CREO QUE ESTO NO SE USA
    local data = string.sub(obj.content[1], offset, (offset+size)) --JV: WATCH OUT WITH THE LOCAL STUFF... WHEN PUT INSIDE THE IF
    --end --JV: CORRESPONDS TO THE IF ABOVE

    reportlog("read: for filename="..filename.." returns",{data=data})

    --return 0, tjoin(data,"") --JV: REMOVED FOR REPLACEMENT WITH DISTDB; data IS ALREADY A STRING
    return 0, data --JV: ADDED FOR REPLACEMENT WITH DISTDB
end,

write = function(self, filename, buf, offset, obj)
    --logs entrance
    reportlog("write: ENTERED for filename="..filename, {buf=buf,offset=offset,obj=obj})

    obj.changed = true
    local size = #buf
    
    --[[
    local o = offset % mem_block_size
    local block = floor(offset / mem_block_size)
    if o == 0 and size % mem_block_size == 0 then
        local start = 0
        for i=block, block + floor(size/mem_block_size) - 1 do
            obj.content[i] = buf:sub(start + 1, start + mem_block_size)
            start = start + mem_block_size
        end
    else
        local start = 0
        while size > 0 do
            local x = obj.content[block] or blank_block
            local b_size = mem_block_size - o 
            if b_size > size then b_size = size end
            obj.content[block] = tjoin({x:sub(1, o), buf:sub(start+1, start + b_size), x:sub(o + 1 + b_size)},"")
            o = 0
            size = size - b_size
            block = block + 1
        end
    end --JV: NOT NEEDED FOR THE MOMENT
    --]]
    reportlog("write: CHECKPOINT1",{})
    if not obj.content[1] then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        obj.content[1] = "" --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("write: CHECKPOINT1a",{})
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    reportlog("write: CHECKPOINT2",{})
    local old_content = obj.content[1] --JV: ADDED FOR REPLACEMENT WITH DISTDB
    local old_size = string.len(obj.content[1])
    if (offset+size) < old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        obj.content[1] = string.sub(old_content, 1, offset)..buf..string.sub(old_content, (offset+size+1), -1) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("write: CHECKPOINT3a",{})
    else --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("write: CHECKPOINT3b",{})
        obj.content[1] = string.sub(old_content, 1, offset)..buf --JV: ADDED FOR REPLACEMENT WITH DISTDB
        if (offset+size) > old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
            reportlog("write: CHECKPOINT3c",{})
            obj.meta.size = offset+size --JV: ADDED FOR REPLACEMENT WITH DISTDB
            obj.meta_changed = true --JV: ADDED FOR REPLACEMENT WITH DISTDB
        end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB

    --local eof = offset + #buf --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    --if eof > obj.meta.size then obj.meta.size = eof ; obj.meta_changed = true end --JV: REMOVED FOR REPLACEMENT WITH DISTDB

    local ok_writedb = put_inodewritedb(filename, obj) --JV: ADDED FOR REPLACEMENT WITH DISTDB

    return #buf
end,

open = function(self, filename, mode) --NOTE: MAYBE OPEN DOESN'T DO ANYTHING BECAUSE OF THE SHARED NATURE OF THE FILESYSTEM; EVERY WRITE READ MUST BE ATOMIC AND
--LONG SESSIONS WITH THE LIKES OF OPEN HAVE NO SENSE.
    --logs entrance
    reportlog("open: ENTERED for filename="..filename, {mode=mode})

    local m = mode % 4
    local inode = get_inode_from_filename(filename)
    --TODO: CHECK THIS MODE THING
    if not inode then return ENOENT end
    inode.open = (inode.open or 0) + 1
    put_inode(inode.meta.ino, inode)
    --TODO: CONSIDER CHANGING A FIELD OF THE DISTDB WITHOUT RETRIEVING THE WHOLE OBJECT; DIFFERENTIAL WRITE
    return 0, inode
end,

release = function(self, filename, inode) --NOTE: RELEASE DOESNT SEEM TO MAKE MUCH SENSE
    --logs entrance
    reportlog("release: ENTERED for filename="..filename, {inode=inode})

    inode.open = inode.open - 1
    if inode.open < 1 then
        if inode.changed then
            local ok_put_inode = put_inode(inode.ino, inode)
        end
        if inode.meta_changed then
            local ok_put_inode = put_inode(inode.ino, inode)
        end
        inode.meta_changed = nil
        inode.changed = nil
    end
    return 0
end,

fgetattr = function(self, filename, obj, ...) --TODO: CHECK IF fgetattr IS USEFUL
    --logs entrance
    reportlog("fgetattr: ENTERED for filename="..filename, {obj=obj})

    local x = obj.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

rmdir = function(self, filename)
    --logs entrance
    reportlog("rmdir: ENTERED for filename="..filename, {})

    local inode_n = get_inode_n(filename)

    if inode_n then --TODO: WATCH OUT, I PUT THIS IF
        local dir, base = filename:splitfilename()

        --local inode = get_inode_from_filename(filename)
        --TODO: CHECK WHAT HAPPENS WHEN TRYING TO ERASE A NON-EMPTY DIR
        --reportlog("rmdir: got inode", {inode, inode})

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
    reportlog("mkdir: ENTERED for filename="..filename, {mode=mode})

    local inode = get_inode_from_filename(filename)

    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = get_inode(0)
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
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        local ok_put_inode = put_inode(greatest_ino, inode)
        local ok_put_file = put_file(filename, greatest_ino)
        local ok_put_root_inode = put_inode(0, root_inode)
    end
    return 0
end,

create = function(self, filename, mode, flag, ...)
    --logs entrance
    reportlog("create: ENTERED for filename="..filename,{mode=mode,flag=flag})

    local inode = get_inode_from_filename(filename)

    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = get_inode(0)
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
        parent.meta.nlink = parent.meta.nlink + 1
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        local ok_put_inode = put_inode(greatest_ino, inode)
        local ok_put_file = put_file(filename, greatest_ino)
        local ok_put_root_inode = put_inode(0, root_inode)
        return 0,o
    end
end,

flush = function(self, filename, obj)
    --logs entrance
    reportlog("flush: ENTERED for filename="..filename, {obj=obj})

    if obj.changed then
        --TODO: CHECK WHAT TO DO HERE, IT WAS MNODE.FLUSH, AN EMPTY FUNCTION
    end
    return 0
end,

readlink = function(self, filename)
    --logs entrance
    reportlog("readlink: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    if inode then
        return 0, inode.content[1]
    end
    return ENOENT
end,

symlink = function(self, from, to)
    --logs entrance
    reportlog("symlink: ENTERED",{from=from,to=to})

    local inode = get_inode_from_filename(filename)

    if not inode then
        
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        local root_inode = get_inode(0)
        root_inode.meta.xattr.greatest_inode_n = root_inode.meta.xattr.greatest_inode_n + 1
        local greatest_ino = root_inode.meta.xattr.greatest_inode_n
        
        local uid, gid, pid = fuse.context()
        
        inode = {
            meta = {
                mode= S_IFLNK+mk_mode(7,7,7),
                ino = greatest_ino, 
                dev = 0, 
                nlink = 1, uid = uid, gid = gid, size = string.len(from), atime = now(), mtime = now(), ctime = now()
            },
            content = {}
        }
        
        parent.content[base]=true
        local ok_put_parent_inode = put_inode(parent.meta.ino, parent)
        local ok_put_inode = put_inode(greatest_ino, inode)
        local ok_put_file = put_file(filename, greatest_ino)
        local ok_put_root_inode = put_inode(0, root_inode)
        return 0
    end
end,

rename = function(self, from, to)
    --logs entrance
    reportlog("rename: ENTERED, from="..from..", to="..to, {})

    if from == to then return 0 end

    local from_inode = get_inode_from_filename(from)
    
    if from_inode then
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
        --TODO: CHECK IF IT IS A DIR

        local ok_put_file = put_file(to, from_inode)
        local ok_delete_file = delete_file(from, from_inode)
        local ok_put_to_parent = put_file(to_dir, to_parent)
        local ok_put_from_parent = put_file(from_dir, from_parent)
        
        if (inode.open or 0) < 1 then
            --mnode.flush_node(inode,to, true) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
            --local ok_writedb_inode = writedb(to, inode) --JV: ADDED FOR REPLACEMENT WITH DISTDB
            --TODO: WTF DO I DO HERE?
        else
            inode.meta_changed = true
        end
        return 0
    end
end,

link = function(self, from, to, ...)
    --logs entrance
    reportlog("link: ENTERED, from="..from..", to="..to, {})
   
    if from == to then return 0 end

    local from_inode = get_inode_from_filename(from)
    
    if from_inode then
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
        from_inode.meta.nlink = from_inode.meta.nlink + 1

        local ok_put_file = put_file(to, from_inode)
        local ok_put_to_parent = put_file(to_dir, to_parent)
        local ok_put_from_parent = put_file(from_dir, from_parent)
        return 0
    end
end,

unlink = function(self, filename, ...)
    --logs entrance
    reportlog("unlink: ENTERED for filename="..filename, {})

    local inode = get_inode_from_filename(filename)
    
    if inode then
        local dir, base = filename:splitfilename()
        local parent = get_inode_from_filename(dir)
        
        parent.content[base] = nil
        inode.meta.nlink = inode.meta.nlink - 1
        if inode.meta.nlink == 0 then
            delete_inode(inode.meta.ino, inode)
        end

        --TODO: MAYBE IF 
        local ok_delete_file = delete_file(filename, inode)
        local ok_put_parent = put_file(dir, parent)
        return 0
    else
        reportlog("unlink: ERROR no inode", {})
        return ENOENT
    end
end,

chown = function(self, filename, uid, gid)
    --logs entrance
    reportlog("chown: ENTERED for filename="..filename..", uid="..uid..", gid="..gid})

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
    reportlog("chmod: ENTERED for filename="..filename, {mode=mode})

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
    reportlog("utime: ENTERED for filename="..filename, {atime=atime,mtime=mtime})

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
    reportlog("ftruncate: ENTERED for filename="..filename, {size=size,obj=obj})
    --TODO: PA DESPUES
    --local old_size = obj.meta.size
    --obj.meta.size = size
    --clear_buffer(obj, floor(size/mem_block_size), floor(old_size/mem_block_size))
    return 0
end,

truncate = function(self, filename, size)
    --logs entrance
    reportlog("truncate: ENTERED for filename="..filename, {size=size})
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
    reportlog("access: ENTERED",{})

    return 0
end,
fsync = function(self, filename, isdatasync, obj)
    --logs entrance
    reportlog("fsync: ENTERED for filename="..filename, {isdatasync=isdatasync,obj=obj})
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
    reportlog("fsyncdir: ENTERED for filename="..filename, {isdatasync=isdatasync,obj=obj})

    return 0
end,
listxattr = function(self, filename, size)
    --logs entrance
    reportlog("listxattr: ENTERED for filename="..filename, {size=size})

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
    reportlog("removexattr: ENTERED for filename="..filename, {name=name})

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
    reportlog("setxattr: ENTERED for filename="..filename, {name=name,val=val,flags=flags})

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
    reportlog("getxattr: ENTERED for filename="..filename, {name=name,size=size})

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
