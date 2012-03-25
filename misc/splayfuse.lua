#!/usr/bin/env lua
--[[
    Memory FS in FUSE using the lua binding
    Copyright 2007 (C) gary ng <linux@garyng.com>

    This program can be distributed under the terms of the GNU LGPL.
]]

local fuse = require 'fuse'
local mnode = require 'mnode'
local dbclient = require 'distdb-client' -- JV: ADDED
local json = require'json' -- JV: ADDED
local crypto = require'crypto' -- JV: ADDED

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
local mem_block_size = 4096 --this seems to be the optimal size for speed and memory
local blank_block=("0"):rep(mem_block_size)
local open_mode={'rb','wb','rb+'}




--BEGIN ADDED BY JV
local db_port = 16501

function reportlog(function_name, args)
    local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")
    logfile1:write(now()..": "..function_name.."\n")
    logfile1:write(print_tablez("args", 0, args))
    logfile1:write("\n")
    logfile1:close()
end

function writedb(path, obj)
    local db_key = crypto.evp.digest("sha1", path) --JV: ADDED FOR REPLACEMENT WITH DISTDB
    local obj_jsoned = json.encode(obj) --JV: ADDED FOR REPLACEMENT WITH DISTDB
    reportlog("writedb: about to write in distdb:",{path=path,obj=obj,db_key=db_key,obj_jsoned=obj_jsoned}) -- JV: ADDED FOR LOGGING
    return send_put(db_port, "consistent", db_key, obj_jsoned)
end

function readdb(path)
    local db_key = crypto.evp.digest("sha1", path) --JV: ADDED FOR REPLACEMENT WITH DISTDB
    reportlog("readdb: about to read in distdb:",{path=path,db_key=db_key}) -- JV: ADDED FOR LOGGING
    local ok_send_get, obj_jsoned = send_get(db_port, "consistent", db_key)
    if not ok_send_get then
        return false
    end
    reportlog("readdb: obj jsoned:",{obj_jsoned=obj_jsoned}) -- JV: ADDED FOR LOGGING
    local obj = json.decode(obj_jsoned)
    return true, obj
end

--END ADDED JV




function string:splitpath() 
    local dir,file = self:match("(.-)([^:/\\]*)$")
    local dirmatch = dir:match("(.-)[/\\]?$")
    if dir == "/" then
        return dir, file
    else
        return dir:match("(.-)[/\\]?$"), file
    end
end

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

local function decode_acl(s) --JV: NOTHING TO CHANGE

    reportlog("decode_acl", {s=s}) -- JV: ADDED FOR LOGGING

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

local function clear_buffer(dirent,from,to) --JV: NOTHING TO CHANGE

    reportlog("clear_buffer: ENTERED", {dirent=dirent, from=from, to=to}) -- JV: ADDED FOR LOGGING

    for i = from, to do dirent.content[i] = nil end
    --[[
    if type(dirent.content) == "table" then
        for i=from,to do dirent.content[i] = nil end
    end
    ]]
    collectgarbage("collect")
end

local function mk_mode(owner, group, world, sticky) --JV: NOTHING TO CHANGE

    reportlog("mk_mode: ENTERED", {owner=owner, group=group, world=world, sticky=sticky}) -- JV: ADDED FOR LOGGING

    sticky = sticky or 0
    local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID -- JV: ADDED FOR LOGGING
    reportlog("mk_mode returns", {result_mode=result_mode}) -- JV: ADDED FOR LOGGING
    return owner * S_UID + group * S_GID + world + sticky * S_SID
end

local function dir_walk(root, path)

    reportlog("dir_walk: ENTERED for path="..path, {}) -- JV: ADDED FOR LOGGING

    local dirent, parent, obj = root, nil, nil
    if path ~= "/" then 
        local progressive_path = ""
        --reportlog("dir_walk: path="..path, {}) -- JV: ADDED FOR LOGGING
        for c in path:gmatch("[^/]*") do
            --reportlog("dir_walk: searching c="..c, {}) -- JV: ADDED FOR LOGGING
            if #c > 0 then --JV: TRYING BY REMOVING THIS
                --reportlog("dir_walk: searching c="..c..">0", {}) -- JV: ADDED FOR LOGGING
                parent = dirent
                --reportlog("dir_walk: CHECKPOINT1", {parent=parent}) -- JV: ADDED FOR LOGGING
                --reportlog("dir_walk: is there parent.content["..c.."]?", {parent_content_c=parent.content[c]}) -- JV: ADDED FOR LOGGING
                --local content = parent.content --JV: REMOVED FOR REPLACEMENT WITH DISTDB
                progressive_path = progressive_path.."/"..c --JV: ADDED FOR REPLACEMENT WITH DISTDB
                --TODO maybe it's possible not to do this recursive search
                --reportlog("dir_walk: progressive_path="..progressive_path, {parent=parent}) -- JV: ADDED FOR LOGGING
                --dirent = content[c]
                --dirent = mnode.get(content[c]) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
                if parent.content[c] then --JV: ADDED FOR REPLACEMENT WITH DISTDB
                    local ok_readdb = false
                    ok_readdb, obj = readdb(progressive_path) --JV: ADDED FOR REPLACEMENT WITH DISTDB
                    if ok_readdb then
                        dirent = obj
                        --reportlog("dir_walk: readdb result", {dirent=dirent}) -- JV: ADDED FOR LOGGING
                    end
                else
                    dirent = nil
                end
            end --JV: TRYING BY REMOVING THIS
            if not dirent then
                reportlog("dir_walk: for path="..path.." returns nil dirent", {parent=parent}) -- JV: ADDED FOR LOGGING
                return nil, parent
            end
        end
    end
    --if true or not dirent.content then --JV: REMOVED, WTF IS A IF TRUE OR ... ?
    if not dirent.content then --JV: ADDED
        reportlog("dir_walk: strange not dirent.content error", {}) -- JV: ADDED FOR LOGGING
        --dirent.content = mnode.get_block(dirent.meta.data_block) --JV: I HOPE THIS NEVER HAPPENS
        dirent.content = {} --JV: ADDED FOR REPLACEMENT WITH DISTDB
        dirent.is_dir = is_dir(dirent.meta.mode)
    end

    reportlog("dir_walk: for path="..path.." returns", {dirent=dirent, parent=parent}) -- JV: ADDED FOR LOGGING

    return dirent, parent
end

local uid,gid,pid,puid,pgid = fuse.context()

--local root = mnode.get("/") --JV: REMOVED FOR REPLACEMENT WITH DISTDB
local ok_read_rootdb, rootdb = readdb("/") --JV: ADDED FOR REPLACEMENT WITH DISTDB

--if not root then --JV: REMOVED FOR REPLACEMENT WITH DISTDB
if not rootdb then --JV: ADDED FOR REPLACEMENT WITH DISTDB

    reportlog("creating root",{content=content}) -- JV: ADDED FOR LOGGING

    --[[
    local content = mnode.block()
    root = mnode.node{
     meta = {
            data_block = content._key,
            xattr={[-1]=true},
            mode= mk_mode(7,5,5) + S_IFDIR, 
            ino = 0, 
            dev = 0, 
            nlink = 2, uid = puid, gid = pgid, size = 0, atime = now(), mtime = now(), ctime = now()}
            ,
            content = content
    }
    --]] --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    
    rootdb = {
        meta = {
            xattr ={[-1]=true},
            mode  = mk_mode(7,5,5) + S_IFDIR,
            ino   = 0,
            dev   = 0, 
            nlink = 2, uid = puid, gid = pgid, size = 0, atime = now(), mtime = now(), ctime = now()
        },
        content = {}
    } -- JV: ADDED FOR REPLACEMENT WITH DISTDB
        
    --mnode.set("/", root) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    writedb("/", rootdb) --JV: ADDED FOR REPLACEMENT WITH DISTDB
end

local function unlink_node(dirent, path) --JV: PA DESPUÉS

    reportlog("unlink_mode: ENTERED", {dirent=dirent, path=path}) -- JV: ADDED FOR LOGGING

    local meta = dirent.meta
    meta.nlink = meta.nlink - 1 - (is_dir(meta.mode) and 1 or 0)
    if meta.nlink == 0 then
        clear_buffer(dirent, 0, floor(dirent.meta.size/mem_block_size))
        dirent.content = nil
        dirent.meta = nil
        mnode.set(dirent._key, nil)
    else
        if (dirent.open or 0) < 1 then mnode.flush_node(dirent, path, true) 
        else dirent.meta_changed = true end
    end
end

local memfs={

pulse=function() --JV: NOTHING TO CHANGE
    
    reportlog("pulse: ENTERED", {}) -- JV: ADDED FOR LOGGING

    print "periodic pulse"
end,

getattr=function(self, path) --JV: NOTHING TO CHANGE

    reportlog("getattr: ENTERED",{path=path}) -- JV: ADDED FOR LOGGING

    local dirent = dir_walk(rootdb, path)
    reportlog("getattr: for path="..path.." dir_walk returned:",{dirent=dirent}) -- JV: ADDED FOR LOGGING
    if not dirent then return ENOENT end
    local x = dirent.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

opendir = function(self, path) --JV: NOTHING TO CHANGE

    reportlog("opendir: ENTERED",{path=path}) -- JV: ADDED FOR LOGGING

    local dirent = dir_walk(rootdb, path)
    reportlog("opendir: for path="..path.." dir_walk returned",{dirent=dirent}) -- JV: ADDED FOR LOGGING
    if not dirent then return ENOENT end
    return 0, dirent
end,

readdir = function(self, path, offset, dirent)

    reportlog("readdir: ENTERED",{path=path,offset=offset,dirent=dirent}) -- JV: ADDED FOR LOGGING

    local out={'.','..'}
    --for k,v in dirent.content do --JV: REMOVED
    for k,v in pairs(dirent.content) do --JV: ADDED (CORRECTING THE LACK OF WORD 'PAIRS'...)
        if type(k) == "string" then out[#out+1] = k end

        --out[#out+1]={d_name=k, ino = v.meta.ino, d_type = v.meta.mode, offset = 0}
    end
    return 0, out
    --return 0, {{d_name="abc", ino = 1, d_type = S_IFREG + 7*S_UID, offset = 0}}
end,

releasedir = function(self, path, dirent) --JV: NOTHING TO CHANGE

    reportlog("releasedir: ENTERED",{path=path,dirent=dirent}) -- JV: ADDED FOR LOGGING

    return 0
end,

mknod = function(self, path, mode, rdev) --JV: NOT SURE IF TO CHANGE OR NOT....!!!

    reportlog("mknod: ENTERED",{path=path,mode=mode,rdev=rdev}) -- JV: ADDED FOR LOGGING

    local dir, base = path:splitpath()
    local dirent, parent = dir_walk(rootdb, path)
    local uid, gid, pid = fuse.context()
    
    --[[
    local content = mnode.block()
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode = mode,
        ino = 0, 
        dev = rdev, 
        nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    local o = mnode.node{ meta=x , content = content}
    --]] --JV: REMOVED FOR REPLACEMENT WITH DISTDB

    local o = {
        meta = {
            xattr={[-1]=true},
            mode = mode,
            ino = 0, 
            dev = rdev, 
            nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()
        },
        content = {}
    } --JV: ADDED FOR REPLACEMENT WITH DISTDB
    o.content[1] = "" --JV: ADDED FOR REPLACEMENT WITH DISTDB



    if not dirent then
        --local content = parent.content --JV: REMOVED FOR REPLACEMENT WITH DISTDB
        --content[base]=o._key --JV: REMOVED FOR REPLACEMENT WITH DISTDB
        parent.content[base]=true --JV: ADDED FOR REPLACEMENT WITH DISTDB
        parent.meta.nlink = parent.meta.nlink + 1
        --mnode.flush_node(parent, dir, true) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
        --mnode.flush_node(o, path, true) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
        local ok_writedb_obj = writedb(dir, parent) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        local ok_writedb_obj = writedb(path, o) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        return 0,o
    end
end,

read=function(self, path, size, offset, obj)
    
    reportlog("read: ENTERED for path="..path,{size=size,offset=offset,obj=obj}) -- JV: ADDED FOR LOGGING

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

    reportlog("read: for path="..path.." the full content of obj:",{obj_content=obj.content}) -- JV: ADDED FOR LOGGING

    --if size + offset < string.len(obj.content[1]) then -- JV: CREO QUE ESTO NO SE USA
    local data = string.sub(obj.content[1], offset, (offset+size)) --JV: WATCH OUT WITH THE LOCAL STUFF... WHEN PUT INSIDE THE IF
    --end --JV: CORRESPONDS TO THE IF ABOVE

    reportlog("read: for path="..path.." returns",{data=data}) -- JV: ADDED FOR LOGGING

    --return 0, tjoin(data,"") --JV: REMOVED FOR REPLACEMENT WITH DISTDB; data IS ALREADY A STRING
    return 0, data --JV: ADDED FOR REPLACEMENT WITH DISTDB
end,

write=function(self, path, buf, offset, obj)
        
    reportlog("write: ENTERED",{path=path,buf=buf,offset=offset,obj=obj}) -- JV: ADDED FOR LOGGING

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
    reportlog("write: CHECKPOINT1",{}) -- JV: ADDED FOR LOGGING
    if not obj.content[1] then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        obj.content[1] = "" --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("write: CHECKPOINT1a",{}) -- JV: ADDED FOR LOGGING
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    reportlog("write: CHECKPOINT2",{}) -- JV: ADDED FOR LOGGING
    local old_content = obj.content[1] --JV: ADDED FOR REPLACEMENT WITH DISTDB
    local old_size = string.len(obj.content[1])
    if (offset+size) < old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
        obj.content[1] = string.sub(old_content, 1, offset)..buf..string.sub(old_content, (offset+size+1), -1) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("write: CHECKPOINT3a",{}) -- JV: ADDED FOR LOGGING
    else --JV: ADDED FOR REPLACEMENT WITH DISTDB
        reportlog("write: CHECKPOINT3b",{}) -- JV: ADDED FOR LOGGING
        obj.content[1] = string.sub(old_content, 1, offset)..buf --JV: ADDED FOR REPLACEMENT WITH DISTDB
        if (offset+size) > old_size then --JV: ADDED FOR REPLACEMENT WITH DISTDB
            reportlog("write: CHECKPOINT3c",{}) -- JV: ADDED FOR LOGGING
            obj.meta.size = offset+size --JV: ADDED FOR REPLACEMENT WITH DISTDB
            obj.meta_changed = true --JV: ADDED FOR REPLACEMENT WITH DISTDB
        end --JV: ADDED FOR REPLACEMENT WITH DISTDB
    end --JV: ADDED FOR REPLACEMENT WITH DISTDB

    --local eof = offset + #buf --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    --if eof > obj.meta.size then obj.meta.size = eof ; obj.meta_changed = true end --JV: REMOVED FOR REPLACEMENT WITH DISTDB

    local ok_writedb = writedb(path, obj) --JV: ADDED FOR REPLACEMENT WITH DISTDB

    return #buf
end,

open=function(self, path, mode)

    reportlog("open: ENTERED",{path=path,mode=mode}) -- JV: ADDED FOR LOGGING

    local m = mode % 4
    local dirent = dir_walk(rootdb, path)
    if not dirent then return ENOENT end
    dirent.open = (dirent.open or 0) + 1
    return 0, dirent
end,

release=function(self, path, obj)

    reportlog("release: ENTERED",{path=path,obj=obj}) -- JV: ADDED FOR LOGGING

    local dir, base = path:splitpath()
    obj.open = obj.open - 1
    if obj.open < 1 then
        if obj.changed then
            local final_key = mnode.flush_data(obj.content, obj, path, true)
            if final_key and final_key ~= obj.data_block then obj.data_block = final_key end
        end
        if obj.meta_changed or obj.parent then mnode.flush_node(obj, path, true) end
        if obj.parent then 
            if final_key and final_key ~= obj.data_block then 
                parent.content[base] = final_key 
            end
            mnode.flush_node(obj.parent, dir, true) 
        end
        obj.parent = nil
        obj.meta_changed = nil
        obj.changed = nil
    end
    return 0
end,

fgetattr=function(self, path, obj, ...)

    reportlog("fgetattr: ENTERED",{path=path,obj=obj}) -- JV: ADDED FOR LOGGING

    local x = obj.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

rmdir = function(self, path)

    reportlog("rmdir: ENTERED",{path=path}) -- JV: ADDED FOR LOGGING

    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(rootdb, path)
    parent.content[base] = nil; mnode.set(dirent._key, nil)
    parent.meta.nlink = parent.meta.nlink - 1
    mnode.flush_node(parent, dir, true)
    return 0
end,

mkdir = function(self, path, mode, ...)

    reportlog("mkdir: ENTERED",{path=path,mode=mode}) -- JV: ADDED FOR LOGGING

    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(rootdb, path)
    local uid,gid,pid = fuse.context()
    
    --[[
    local content = mnode.block{[-1]=true}
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode = set_bits(mode,S_IFDIR), -- mode don't have directory bit set
        ino = 0, 
        dev = 0, 
        nlink = 2, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    local o = mnode.node{ meta=x , content = content, is_dir=true}
    --]] --JV: REMOVED FOR REPLACEMENT WITH DISTDB

    local o = {
        meta = {
            xattr={[-1]=true},
            mode = set_bits(mode,S_IFDIR), -- mode don't have directory bit set
            ino = 0, 
            dev = 0, 
            nlink = 2, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()
        },
        content = {}
    } --JV: ADDED FOR REPLACEMENT WITH DISTDB

    if not dirent then
        --local content = parent.content
        parent.content[base]= true
        parent.meta.nlink = parent.meta.nlink + 1
        --mnode.flush_node(parent, dir, true)
        --mnode.flush_node(o, path, true)

        reportlog("mkdir: gonna write",{dir=dir,parent=parent,path=path,o=o}) -- JV: ADDED FOR LOGGING

        local ok_writedb_parent = writedb(dir, parent) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        local ok_writedb_obj = writedb(path, o) --JV: ADDED FOR REPLACEMENT WITH DISTDB

    end
    return 0
end,

create = function(self, path, mode, flag, ...)

    reportlog("create: ENTERED",{path=path,mode=mode,flag=flag}) -- JV: ADDED FOR LOGGING

    --if path:find('hidden') then print("create", path, mode, flag) end --JV: REMOVED
    local dir, base = path:splitpath()
    reportlog("create: for path="..path.." dir="..dir..", base="..base, {})
    local dirent,parent = dir_walk(rootdb, path)
    reportlog("create: for path="..path.." dir_walk returned", {dirent=dirent, parent=parent})
    local uid,gid,pid = fuse.context()
    
    --[[
    local content = mnode.block()
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode = set_bits(mode, S_IFREG),
        ino = 0, 
        dev = 0, 
        nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    --local o = mnode.node{ meta=x , content = content } --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    --]] --JV: REMOVED FOR REPLACEMENT WITH DISTDB
    
    local o = {
        meta = {
            xattr ={[-1]=true},
            mode  = set_bits(mode, S_IFREG),
            ino   = 0, 
            dev   = 0, 
            nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()
        },
        content = {}
    } --JV: ADDED FOR REPLACEMENT WITH DISTDB
    o.content[1] = "" --JV: ADDED FOR REPLACEMENT WITH DISTDB

    reportlog("create: CHECKPOINT1",{}) -- JV: ADDED FOR LOGGING
    
    if not dirent then
        --local content = parent.content
        reportlog("create: CHECKPOINT-IF1",{}) -- JV: ADDED FOR LOGGING
        parent.content[base] = true
        reportlog("create: CHECKPOINT-IF2",{}) -- JV: ADDED FOR LOGGING
        parent.meta.nlink = parent.meta.nlink + 1
        --mnode.flush_node(parent, dir, false) --JV: REMOVED FOR REPLACEMENT WITH DISTDB
        reportlog("create: CHECKPOINT-IF3",{}) -- JV: ADDED FOR LOGGING
        o.parent = parent
        reportlog("create: CHECKPOINT-IF4",{}) -- JV: ADDED FOR LOGGING
        o.open = 1
        reportlog("create: CHECKPOINT-IF5",{}) -- JV: ADDED FOR LOGGING

        local ok_writedb_parent = writedb(dir, parent) --JV: ADDED FOR REPLACEMENT WITH DISTDB
        --local ok_writedb_obj = writedb(path, o) --JV: ADDED FOR REPLACEMENT WITH DISTDB APPARENTLY NOT USED???
        

        return 0,o
    end
end,

flush=function(self, path, obj)

    reportlog("flush: ENTERED",{path=path,obj=obj}) -- JV: ADDED FOR LOGGING

    if obj.changed then mnode.flush_data(obj.content, obj, path) end
    return 0
end,

readlink=function(self, path)

    reportlog("readlink: ENTERED",{path=path}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        return 0, dirent.content[1]
    end
    return ENOENT
end,

symlink=function(self, from, to)

    reportlog("symlink: ENTERED",{from=from,to=to}) -- JV: ADDED FOR LOGGING

    local dir, base = to:splitpath()
    local dirent,parent = dir_walk(root, to)
    local uid,gid,pid = fuse.context()
    local content = mnode.block()
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode= S_IFLNK+mk_mode(7,7,7),
        ino = 0, 
        dev = 0, 
        nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    local o = mnode.node{ meta=x , content = content}
    o.content[1] = from
    if not dirent then
        local content = parent.content
        content[base]=o._key
        parent.meta.nlink = parent.meta.nlink + 1
        mnode.flush_node(parent, dir, true)
        mnode.flush_node(o, to, true)
        return 0
    end
end,

rename = function(self, from, to)

    reportlog("rename: ENTERED",{from=from,to=to}) -- JV: ADDED FOR LOGGING

    if from == to then return 0 end

    --print("rename", from, to)
    local dir_f, o_base = from:splitpath()
    local dir_t, base = to:splitpath()
    local dirent,fp = dir_walk(root, from)
    local n_dirent,tp = dir_walk(root, to)
    if dirent then
        tp.content[base]=dirent._key
        if n_dirent then 
            unlink_node(n_dirent, to) 
        else
            tp.meta.nlink = tp.meta.nlink + 1 
        end
        mnode.flush_node(tp, dir_f, true)

        fp.content[o_base]=nil
        fp.meta.nlink = tp.meta.nlink - 1
        mnode.flush_node(fp, dir_t, true)

        if (dirent.open or 0) < 1 then mnode.flush_node(dirent,to, true) 
        else dirent.meta_changed = true end
        return 0
    end
end,

link=function(self, from, to, ...)

    reportlog("link: ENTERED",{from=from,to=to}) -- JV: ADDED FOR LOGGING

    --print("link", from, to)
    local dir, base = to:splitpath()
    local dirent,fp = dir_walk(root, from)
    local n_dirent,tp = dir_walk(root, to)
    if dirent then
        tp.content[base]=dirent._key
        tp.meta.nlink = tp.meta.nlink + 1
        mnode.flush_node(tp, dir, true)
        dirent.meta.nlink = dirent.meta.nlink + 1
        if (dirent.open or 0) < 1 then mnode.flush_node(dirent,to, true) 
        else dirent.meta_changed = true end
        if n_dirent then unlink_node(n_dirent, to) end
        return 0
    end
end,

unlink=function(self, path, ...)

    reportlog("unlink: ENTERED",{path=path}) -- JV: ADDED FOR LOGGING

    if path:find("hidden") then print("unlink", path) end
    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        local meta = dirent.meta
        local content = parent.content
        parent.content[base] = nil
        parent.meta.nlink = parent.meta.nlink - 1
        mnode.flush_node(parent, dir, true)
        unlink_node(dirent, path)
        return 0
    else
        print("unlink failed", path)
        return ENOENT
    end
end,

chown=function(self, path, uid, gid)

    reportlog("chown: ENTERED",{path=path,uid=uid,gid=gid}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        dirent.meta.uid = uid
        dirent.meta.gid = gid
        if (dirent.open or 0) < 1 then mnode.flush_node(dirent, path, true) 
        else dirent.meta_changed = true end
        return 0
    else
        return ENOENT
    end
end,
chmod=function(self, path, mode)

    reportlog("chmod: ENTERED",{path=path,mode=mode}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        dirent.meta.mode = mode
        if (dirent.open or 0) < 1 then mnode.flush_node(dirent, path, true) 
        else dirent.meta_changed = true end
        return 0
    else
        return ENOENT
    end
end,
utime=function(self, path, atime, mtime)

    reportlog("utime: ENTERED",{path=path,atime=atime,mtime=mtime}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        dirent.meta.atime = atime
        dirent.meta.mtime = mtime
        if (dirent.open or 0) < 1 then mnode.flush_node(dirent, path, true) 
        else dirent.meta_changed = true end
        return 0
    else
        return ENOENT
    end
end,
ftruncate = function(self, path, size, obj)

    reportlog("ftruncate: ENTERED",{path=path,size=size,obj=obj}) -- JV: ADDED FOR LOGGING

    local old_size = obj.meta.size
    obj.meta.size = size
    clear_buffer(obj, floor(size/mem_block_size), floor(old_size/mem_block_size))
    return 0
end,

truncate=function(self, path, size)

    reportlog("truncate: ENTERED",{path=path,size=size}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then 
        local old_size = dirent.meta.size
        dirent.meta.size = size
        clear_buffer(dirent, floor(size/mem_block_size), floor(old_size/mem_block_size))
        if (dirent.open or 0) < 1 then mnode.flush_node(dirent, path, true) 
        else dirent.meta_changed = true end
        return 0
    else
        return ENOENT
    end
end,
access=function(...)

    reportlog("access: ENTERED",{}) -- JV: ADDED FOR LOGGING

    return 0
end,
fsync = function(self, path, isdatasync, obj)

    reportlog("fsync: ENTERED",{path=path,isdatasync=isdatasync,obj=obj}) -- JV: ADDED FOR LOGGING

    mnode.flush_node(obj, path, false) 
    if isdatasync and obj.changed then 
        mnode.flush_data(obj.content, obj, path) 
    end
    return 0
end,
fsyncdir = function(self, path, isdatasync, obj)

    reportlog("fsyncdir: ENTERED",{path=path,isdatasync=isdatasync,obj=obj}) -- JV: ADDED FOR LOGGING

    return 0
end,
listxattr = function(self, path, size)

    reportlog("listxattr: ENTERED",{path=path,size=size}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        --return 0, "attr1\0attr2\0attr3\0"
        --return 0, "" --no attributes
        local v={}
        for k in pairs(dirent.meta.xattr) do 
            if type(k) == "string" then v[#v+1]=k end
        end
        --return 0, table.concat(v,"\0") .. "\0"
        return 0, table.concat(v,"\0") .. "\0"
    else
        return ENOENT
    end
end,

removexattr = function(self, path, name)

    reportlog("removexattr: ENTERED",{path=path,name=name}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        dirent.meta.xattr[name] = nil
        return 0
    else
        return ENOENT
    end
end,

setxattr = function(self, path, name, val, flags)

    reportlog("setxattr: ENTERED",{path=path,name=name,val=val,flags=flags}) -- JV: ADDED FOR LOGGING

    --string.hex = function(s) return s:gsub(".", function(c) return format("%02x", string.byte(c)) end) end
    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        dirent.meta.xattr[name]=val
        return 0
    else
        return ENOENT
    end
end,

getxattr = function(self, path, name, size)

    reportlog("getxattr: ENTERED",{path=path,name=name,size=size}) -- JV: ADDED FOR LOGGING

    local dirent,parent = dir_walk(rootdb, path)
    if dirent then
        return 0, dirent.meta.xattr[name] or "" --not found is empty string
    else
        return ENOENT
    end
end,

statfs = function(self,path)
    local dirent,parent = dir_walk(rootdb, path)
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
