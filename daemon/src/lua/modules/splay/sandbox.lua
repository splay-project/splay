--[[
       Splay ### v1.3 ###
       Copyright 2006-2011
       http://www.splay-project.org
]]

--[[
This file is part of Splay.

Splay is free software: you can redistribute it and/or modify 
it under the terms of the GNU General Public License as published 
by the Free Software Foundation, either version 3 of the License, 
or (at your option) any later version.

Splay is distributed in the hope that it will be useful,but 
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Splayd. If not, see <http://www.gnu.org/licenses/>.
]]

--[[
The sandbox receive what it must to keep into as parameters.

It supports copy of modules or env variables. It has a new require() that will
mimic the classical behavior.

This sandbox will provide standard libraries to the sandboxed code, but
will take everything that will be put in from the actual environment
if it's avaible. That means that this sandbox should perfectly works into
another sandbox if needed.

NOTES:

If we would allow getfenv() we should setfenv() all the functions of the sandbox
and deny all the stack accesses except the 1. In these conditions, this function
seems no more very useful.

setfenv cannot be very dangerous, but with 0, it cans change the global env and
override a function called after the sandbox end (like os.exit). But everything
it can put in is from the sandboxed env, so...

Actually we don't create a new env, but we clean the actual one. Since core
functions rely on the "root" env, it's more sure to clean it rather than trying
to build a new one. setfenv() will not work on core functions.

]]

local string = string
local table = table
local math = math
local coroutine = coroutine
local os = os -- Will be restricted later.
local rio = require"splay.restricted_io"
local log = require"splay.log"
local debug = debug -- -- Will be restricted later.
local base = _G
local pairs = pairs
local print = print
local setfenv = setfenv
local type = type
local assert = assert
local loadstring = loadstring
local tonumber = tonumber

local misc = require"splay.misc"

--module("splay.sandbox")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Sandbox"
_M._VERSION     = 1.0

--[[ DEBUG ]]--
_M.l_o = log.new(3, "[splay.sandbox]")

--[[ CODE ]]--

-- generate the new require with old env upvalues
function _M.generate_require(allowed, inits)

	local allowed = allowed or {}
	local inits = inits or {}

	-- Direct link where package will be installed by module() (pointer)
	-- then base.package will be removed (the pointer)
	-- and new_require() will re-create a new one (base.package)
	-- But the new one is a new location and module() will always use the old that
	-- we keep in 'pack' and then copy to the new base.packages when needed.
	local pack = base.package

	local function create_module_global(modname)

		local sa = misc.split(modname, ".")
		local path = base
		for i = 1, #sa do
			local part = sa[i]
			-- A global is on the path but it's something not related with the
			-- package.
			if type(path) ~= "table" then break end
			if not path[part] then 
				path[part] = {}
				if i == #sa then
					_M.l_o:debug("Creating global for "..modname)
					path[part] = base.package.loaded[modname]
				end
			end
			path = path[part]
		end
	end

	local function init(modname)

		if inits[modname] and
				type(base.package.loaded[modname]) == "table" and
				base.package.loaded[modname].init then
			_M.l_o:debug(modname.." initialization.")
			base.package.loaded[modname].init(inits[modname])
		end
	end

	local function finalize(modname)

		base.package.loaded[modname] = pack.loaded[modname]
		init(modname)
		-- Needed only for things alreadly loaded to recreate this in the new
		-- env because they have been deleted before. Anyway, it will never
		-- hurt.
		create_module_global(modname)
		return base.package.loaded[modname]
	end

	-- 1) Load what is autorized.
	-- 2) Load what is in preload table (user modules)
	-- 3) Copy already loaded libraries (maybe they have additional restrictions)
	return function(modname)
		_M.l_o:debug("require() "..modname)

		-- creation of the new base.package that will NOT be directly used by
		-- module()
		if not base.package then base.package = {} end
		if not base.package.loaded then base.package.loaded = {} end
		if not base.package.preload then base.package.preload = {} end

		-- We will have the EXACT behavior for package that will really be
		-- loaded with the new require. We will have a very near behavior
		-- when the package was already loaded.
		--
		-- The problem is, when a package load, it call the loaders function
		-- of the package that generally will touch only
		-- package.loaded[modname] but we can't be sure.
		--
		-- The other problem is the call to module() in the package.
		-- module() can reuse or make global table with the name of the
		-- package.

		-- if the module is in preload table, is an user module, we will load it
		-- anyway
		if base.package.preload[modname] then
			_M.l_o:notice("User module "..modname.." preloaded.")
			base.package.preload[modname]()
			-- we call the function, that contain module(), that will load the
			-- module into the global "modname" and in package.loaded[modname]
			return finalize(modname)
		end

		-- verify if the module can be accepted
		local found = false
		for _, m in pairs(allowed) do
			if m == modname then
				found = true
				break
			end
		end
		if not found then
			_M.l_o:warn("Require of "..modname.." refused")
			return nil, "not permitted"
		end
		_M.l_o:notice("Require of "..modname.." autorized")

		-- package already loaded in the sandbox
		-- Normally it's the loader[1] but it return a string if not found and I
		-- don't like that.
		if base.package.loaded[modname] then
			_M.l_o:notice(modname.." already loaded.")
			return base.package.loaded[modname]
		end

		-- package not loaded but existing in pack (previous env)
		-- (yes we could do that in the form of an additionnal loader)
		if pack.loaded[modname] then
			_M.l_o:notice(modname.." already loaded in previous env.")
			return finalize(modname)
		end

		-- If no mod will be found, we will anyway never search anymore...
		base.package.loaded[modname] = false

		-- Loaders return a string if not found...
		-- Loaders are in package.loaders, so in pack here. And they will work
		-- on the global env and in pack, because pack is their true env, the
		-- new base.package is not.
		for i, loader in pairs(pack.loaders) do
			local p = loader(modname)
			if p and type(p) == "function" then
				_M.l_o:debug(modname.." loader "..i)
				-- will modify pack.loaded[modname]
				local r = p()
				-- return instead of directly setting pack.loaded[modname]
				if r ~= nil then
					pack.loaded[modname] = r
				end
				-- copy from the old env to the new one
				return finalize(modname)
			end
		end
		return base.package.loaded[modname]
	end
end

--[[ Generate a loadstring function that refuse bytecode.
Apparently, there is no security problem with it.
]]
function _M.loadstring_no_bytecode()

	local ls = loadstring

	return function(s)
		-- \x1BLua
		if string.sub(s, 1, 4) == string.char(27, 76, 117, 97) then
			return nil, "Bytecode refused"
		end
		return ls(s)
	end
end
	
-- return secure functions in any situations
function _M.secure_functions()

	--[[
	still denied:

	loadfile
	loadstring
	load
	dofile
	getfenv
	module
	newproxy
	require
	setfenv
	--]]
	return {"assert",
			"collectgarbage",
			"error",
			"gcinfo",
			"getmetatable",
			"ipairs",
			"next",
			"pairs",
			"pcall",
			"print",
			"rawequal",
			"rawget ",
			"rawset",
			"select",
			"setmetatable",
			"tonumber",
			"tostring",
			"type",
			"unpack",
			"xpcall",
			"gettimeofday"}
end

-- secure functions if you work with the true global env
function _M.secure_functions_global()

	--[[
	still denied:

	load
	loadfile
	dofile
	newproxy
	require
	--]]
	return misc.table_concat(_M.secure_functions(), {
			"loadstring",
			"getfenv",
			"module",
			"setfenv"})
end

-- Return os with only secure functions
function _M.secure_os()

	local new = {}
	local allowel_os = {"exit", "date", "difftime", "time", "clock"}
	for _, f in pairs(allowel_os) do
		new[f] = base.os[f]
	end
	return new
end

-- Return debug with only secure functions
function _M.secure_debug()

	local new = {}
	local allowed_debug = {"traceback"}
	for _, f in pairs(allowed_debug) do
		new[f] = base.debug[f]
	end
	return new
end

function _M.sandboxed_denied()
	log:print("This function is sandboxed -- usage not allowed. Aborting in 10secs.")
	events.exit()
	os.exit()
end
-- Replace a sandboxed function with a stub function.
function _M.load_sandboxed_func(name)
	if type(base[name]) == "function" then
		return _M.sandboxed_denied
	else
		return nil
	end
end

-- Only keep in the environment what is in the keep list.
function _M.clean_env(keep_list)
	local remove_list = {}
	for name, val in pairs(base) do
		local found = false
		for _, n in pairs(keep_list) do
			if n == name then
				found = true
				break
			end
		end
		if not found then
			remove_list[#remove_list + 1] = name
		end
	end
	for _, name in pairs(remove_list) do
		_M.l_o:notice("removing: "..name.." (type: "..type(base[name])..")")
		base[name] = _M.load_sandboxed_func(name)
	end
end

-- Will limit the root env.
--
-- socket will already be a SE: RS: socket, so when it will be copied, it will
-- then be init() without problems.
function _M.protect_env(settings)
	if not settings then
		return nil, "missing settings"
	end
	if not settings.io then
		return nil, "missing IO configuration"
	end

	settings.globals = settings.globals or {}
	settings.allowed = settings.allowed or {}
	settings.inits = settings.inits or {}
	
	globals = misc.table_concat(settings.globals,
			{"string", "table", "math", "coroutine", "os", "io","debug"})
	allowed = misc.table_concat(settings.allowed,
			{"string", "table", "math", "coroutine", "os", "io","debug"})

	rio.init(settings.io)
	base.io = rio
	base.package.loaded.io = base.io

	base.os = _M.secure_os()
	-- link to restricted_io
	base.os.remove = base.io.remove
	base.os.rename = base.io.rename
	base.os.tmpname = base.io.tmpname
	
	base.debug = _M.secure_debug()
	
	-- New (secure) require()
	base.require = _M.generate_require(allowed, settings.inits)

	-- New loadstring not accepting bytecode
	--base.loadstring = loadstring_no_bytecode()

	-- Remove everything except authorized globals (and secure functions)
	local sf = _M.secure_functions_global()
	sf[#sf + 1] = "require"
	_M.clean_env(misc.table_concat(globals, sf))
end

return _M
