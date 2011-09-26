--[[
       Splay ### v1.0.6 ###
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
NOTE:

Meta-module

This module create the base splay socket. It will use Luasocket.core (maybe
restricted), add the non blocking events layer and LuaSocket improved helpers.
The final socket will be in any case a fully LuaSocket compatible socket. In
collaboration with Events, you will be able to use this socket as a blocking
socket even if behind the scene, the socket is non blocking and Events will call
select() when needed.

When you need a socket, in any file, require this one.
--]]

-- If socket exists, it can be a socket.core + restricted.
if not socket then
	socket = require"socket.core"
end

-- kept global to be able to change the debug level easily (without having to
-- require splay.socket_events before splay.base), only useful locally
socket_events = require"splay.socket_events"

local lsh = require"splay.luasocket"

-- We can't wrap in the other order because there is in luasocket 2 aliases
-- (connect() and bind() that have the same name than the low level socket
-- functions)
socket = lsh.wrap(socket_events.wrap(socket))

-- very important, for other package that need a full luasocket like
-- socket.http, ...
package.loaded["socket"] = socket

-- These 2 lines are equal...
--package.loaded["splay.socket"] = socket
return socket
