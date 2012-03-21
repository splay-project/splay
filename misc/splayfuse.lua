#!/usr/bin/env lua
--[[
    Memory FS in FUSE using the lua binding
    Copyright 2007 (C) gary ng <linux@garyng.com>

    This program can be distributed under the terms of the GNU LGPL.
]]

local fuse = require 'fuse'
local mnode = require 'mnode'
local dbclient = require 'distdb-client'

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
local db_port = 15009
local db_key = "4cded69480ba330e54d30964ac6e55c7d350d642"

function print_tablez(name, order, input_table)
    local output_string = ""
    local indentation = ""
    for i=1,order do
        indentation = indentation.."\t"
    end
    for i,v in pairs(input_table) do
        if type(v) == "string" or type(v) == "number" then
            output_string = output_string..indentation..name.."."..i.." = "..v.."\n"
        elseif type(v) == "boolean" then
            if v == true then
                output_string = output_string..indentation..name.."."..i.." = true\n"
            else
                output_string = output_string..indentation..name.."."..i.." = false\n"
            end
        elseif type(v) == "table" then
            output_string = output_string..indentation..name.."."..i.." type table:\n"
            output_string = output_string..print_tablez(i, order+1, v)
        else
            output_string = output_string..indentation..name.."."..i.." type "..type(v).."\n"
        end
    end
    return output_string
end

function reportlog(function_name, args)
    local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")
    logfile1:write("exec function "..function_name.."\n")
    logfile1:write(print_tablez("args", 0, args))
    logfile1:write("\n")
    logfile1:close()
end
--END ADDED JV




function string:splitpath() 
    local dir,file = self:match("(.-)([^:/\\]*)$") 
    return dir:match("(.-)[/\\]?$"), file
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

local function decode_acl(s)

    reportlog("decode_acl", {s=s})

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

local function clear_buffer(dirent,from,to)

    reportlog("clear_buffer", {dirent=dirent, from=from, to=to})

    for i = from, to do dirent.content[i] = nil end 
    --[[
    if type(dirent.content) == "table" then
        for i=from,to do dirent.content[i] = nil end
    end
    ]]
    collectgarbage("collect")
end

local function mk_mode(owner, group, world, sticky)

    reportlog("mk_mode", {owner=owner, group=group, world=world, sticky=sticky})

    sticky = sticky or 0
    local result_mode = owner * S_UID + group * S_GID + world + sticky * S_SID --ADDED BY JV
    reportlog("mk_mode returns", {result_mode=result_mode})
    return owner * S_UID + group * S_GID + world + sticky * S_SID
end

local function dir_walk(root, path)

    reportlog("dir_walk", {root=root, path=path})

    local dirent , parent = root, nil
    if path ~= "/" then 
        for c in path:gmatch("[^/]*") do
            if #c > 0 then
                reportlog("dir_walk searching", {c=c})
                parent = dirent
                local content = parent.content
                --dirent = content[c]
                dirent = mnode.get(content[c])
            end
            if not dirent then return nil, parent end
        end
    end
    if true or not dirent.content then 
        dirent.content = mnode.get_block(dirent.meta.data_block) 
        dirent.is_dir = is_dir(dirent.meta.mode)
    end

    reportlog("dir_walk_returns", {dirent=dirent, parent=parent})

    return dirent, parent
end

local uid,gid,pid,puid,pgid = fuse.context()

local root = mnode.get("/")

if not root then
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
    mnode.set("/", root)
end

local function unlink_node(dirent, path)

    reportlog("unlink_mode", {dirent=dirent, path=path})

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

pulse=function()
    
    reportlog("pulse", {})

    print "periodic pulse"
end,

getattr=function(self, path)

    reportlog("getattr",{path=path})

    local dirent = dir_walk(root, path)
    if not dirent then return ENOENT end
    local x = dirent.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

opendir = function(self, path)

    reportlog("opendir",{path=path})

    local dirent = dir_walk(root, path)
    if not dirent then return ENOENT end
    return 0, dirent
end,

readdir = function(self, path, offset, dirent)

    reportlog("readdir",{path=path,offset=offset,dirent=dirent})

    local out={'.','..'}
    for k,v in dirent.content do 
        if type(k) == "string" then out[#out+1] = k end

        --out[#out+1]={d_name=k, ino = v.meta.ino, d_type = v.meta.mode, offset = 0}
    end
    return 0, out
    --return 0, {{d_name="abc", ino = 1, d_type = S_IFREG + 7*S_UID, offset = 0}}
end,

releasedir = function(self, path, dirent)

    reportlog("releasedir",{path=path,dirent=dirent})

    return 0
end,

mknod = function(self, path, mode, rdev)

    reportlog("mknod",{path=path,mode=mode,rdev=rdev})

    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(root, path)
    local uid,gid,pid = fuse.context()
    local content = mnode.block()
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode = mode,
        ino = 0, 
        dev = rdev, 
        nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    local o = mnode.node{ meta=x , content = content}
    if not dirent then
        local content = parent.content
        content[base]=o._key
        parent.meta.nlink = parent.meta.nlink + 1
        mnode.flush_node(parent, dir, true)
        mnode.flush_node(o, path, true)
        return 0,o
    end
end,

read=function(self, path, size, offset, obj)
    
    reportlog("read",{path=path,size=size,offset=offset,obj=obj})

    local block = floor(offset/mem_block_size)
    local o = offset%mem_block_size
    local data={}
    
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
    end

    --local filecontent = send_get(db_port, "evtl_consistent", db_key);

    return 0, tjoin(data,"")
end,

write=function(self, path, buf, offset, obj)
        
    reportlog("write",{path=path,buf=buf,offset=offset,obj=obj})

    obj.changed = true
    local size = #buf
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
    end
    local eof = offset + #buf
    if eof > obj.meta.size then obj.meta.size = eof ; obj.meta_changed = true end

    --send_put(db_port, "evtl_consistent", db_key, "helloworld");
    

    return #buf
end,

open=function(self, path, mode)

    reportlog("open",{path=path,mode=mode})

    local m = mode % 4
    local dirent = dir_walk(root, path)
    if not dirent then return ENOENT end
    dirent.open = (dirent.open or 0) + 1
    return 0, dirent
end,

release=function(self, path, obj)

    reportlog("release",{path=path,obj=obj})

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

    reportlog("fgetattr",{path=path,obj=obj})

    local x = obj.meta
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

rmdir = function(self, path)

    reportlog("rmdir",{path=path})

    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(root, path)
    parent.content[base] = nil; mnode.set(dirent._key, nil)
    parent.meta.nlink = parent.meta.nlink - 1
    mnode.flush_node(parent, dir, true)
    return 0
end,

mkdir = function(self, path, mode, ...)

    reportlog("mkdir",{path=path,mode=mode})

    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(root, path)
    local uid,gid,pid = fuse.context()
    local content = mnode.block{[-1]=true}
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode = set_bits(mode,S_IFDIR), -- mode don't have directory bit set
        ino = 0, 
        dev = 0, 
        nlink = 2, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    local o = mnode.node{ meta=x , content = content, is_dir=true}
    if not dirent then
        local content = parent.content
        content[base]=o._key
        parent.meta.nlink = parent.meta.nlink + 1
        mnode.flush_node(parent, dir, true)
        mnode.flush_node(o, path, true)
    end
    return 0
end,

create = function(self, path, mode, flag, ...)

    reportlog("create",{path=path,mode=mode,flag=flag})

    if path:find('hidden') then print("create", path, mode, flag) end
    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(root, path)
    local uid,gid,pid = fuse.context()
    local content = mnode.block()
    local x = {
        data_block = content._key,
        xattr={[-1]=true},
        mode = set_bits(mode, S_IFREG),
        ino = 0, 
        dev = 0, 
        nlink = 1, uid = uid, gid = gid, size = 0, atime = now(), mtime = now(), ctime = now()}
    local o = mnode.node{ meta=x , content = content }
    if not dirent then
        local content = parent.content
        content[base]=o._key
        parent.meta.nlink = parent.meta.nlink + 1
        mnode.flush_node(parent, dir, false)
        o.parent = parent
        o.open = 1
        return 0,o
    end
end,

flush=function(self, path, obj)

    reportlog("flush",{path=path,obj=obj})

    if obj.changed then mnode.flush_data(obj.content, obj, path) end
    return 0
end,

readlink=function(self, path)

    reportlog("readlink",{path=path})

    local dirent,parent = dir_walk(root, path)
    if dirent then
        return 0, dirent.content[1]
    end
    return ENOENT
end,

symlink=function(self, from, to)

    reportlog("symlink",{from=from,to=to})

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

    reportlog("rename",{from=from,to=to})

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

    reportlog("link",{from=from,to=to})

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

    reportlog("unlink",{path=path})

    if path:find("hidden") then print("unlink", path) end
    local dir, base = path:splitpath()
    local dirent,parent = dir_walk(root, path)
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

    reportlog("chown",{path=path,uid=uid,gid=gid})

    local dirent,parent = dir_walk(root, path)
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

    reportlog("chmod",{path=path,mode=mode})

    local dirent,parent = dir_walk(root, path)
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

    reportlog("utime",{path=path,atime=atime,mtime=mtime})

    local dirent,parent = dir_walk(root, path)
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

    reportlog("ftruncate",{path=path,size=size,obj=obj})

    local old_size = obj.meta.size
    obj.meta.size = size
    clear_buffer(obj, floor(size/mem_block_size), floor(old_size/mem_block_size))
    return 0
end,

truncate=function(self, path, size)

    reportlog("truncate",{path=path,size=size})

    local dirent,parent = dir_walk(root, path)
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

    reportlog("access",{})

    return 0
end,
fsync = function(self, path, isdatasync, obj)

    reportlog("fsync",{path=path,isdatasync=isdatasync,obj=obj})

    mnode.flush_node(obj, path, false) 
    if isdatasync and obj.changed then 
        mnode.flush_data(obj.content, obj, path) 
    end
    return 0
end,
fsyncdir = function(self, path, isdatasync, obj)

    reportlog("fsyncdir",{path=path,isdatasync=isdatasync,obj=obj})

    return 0
end,
listxattr = function(self, path, size)

    reportlog("listxattr",{path=path,size=size})

    local dirent,parent = dir_walk(root, path)
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

    reportlog("removexattr",{path=path,name=name})

    local dirent,parent = dir_walk(root, path)
    if dirent then
        dirent.meta.xattr[name] = nil
        return 0
    else
        return ENOENT
    end
end,

setxattr = function(self, path, name, val, flags)

    reportlog("setxattr",{path=path,name=name,val=val,flags=flags})

    --string.hex = function(s) return s:gsub(".", function(c) return format("%02x", string.byte(c)) end) end
    local dirent,parent = dir_walk(root, path)
    if dirent then
        dirent.meta.xattr[name]=val
        return 0
    else
        return ENOENT
    end
end,

getxattr = function(self, path, name, size)

    reportlog("getxattr",{path=path,name=name,size=size})

    local dirent,parent = dir_walk(root, path)
    if dirent then
        return 0, dirent.meta.xattr[name] or "" --not found is empty string
    else
        return ENOENT
    end
end,

statfs = function(self,path)
    local dirent,parent = dir_walk(root, path)
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
