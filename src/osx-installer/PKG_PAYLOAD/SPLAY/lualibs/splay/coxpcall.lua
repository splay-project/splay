-------------------------------------------------------------------------------
-- Coroutine safe xpcall and pcall versions
--
-- Encapsulates the protected calls with a coroutine based loop, so errors can
-- be dealed without the usual Lua 5.x pcall/xpcall issues with coroutines
-- yielding inside the call to pcall or xpcall.
--
-- Authors: Roberto Ierusalimschy and Andre Carregal 
-- Contributors: Thomas Harning Jr., Ignacio Burgueño, Fábio Mascarenhas
--
-- Copyright 2005 - Kepler Project (www.keplerproject.org)
--
-------------------------------------------------------------------------------

-- Leo, made a module from it...

-------------------------------------------------------------------------------
-- Implements xpcall with coroutines
-------------------------------------------------------------------------------
local oldpcall, oldxpcall = pcall, xpcall
local coroutine = require"coroutine"
local debug = require"debug"

module("splay.coxpcall")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Implements xpcall with coroutines"
_VERSION     = 1.0

function handleReturnValue(err, co, status, ...)
    if not status then
        return false, err(debug.traceback(co, (...)), ...)
    end
    if coroutine.status(co) == 'suspended' then
        return performResume(err, co, coroutine.yield(...))
    else
        return true, ...
    end
end

function performResume(err, co, ...)
    return handleReturnValue(err, co, coroutine.resume(co, ...))
end    

local function id(trace, ...)
  return ...
end

function xpcall(f, err, ...)
    local res, co = oldpcall(coroutine.create, f)
    if not res then
        local params = {...}
        local newf = function() return f(unpack(params)) end
        co = coroutine.create(newf)
    end
    return performResume(err, co, ...)
end

function pcall(f, ...)
    return xpcall(f, id, ...)
end
