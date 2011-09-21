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
socket = require"socket.core"
rs=require"splay.restricted_socket"
rs.l_o.level=1
rs.init(
	{max_sockets=1024,
	local_ip="127.0.0.1",
	start_port=11000,end_port=11500}
)
socket=rs.wrap(socket)

require"splay.base"

events.run(function()
	local ip,_ = socket.dns.toip("orion.unine.ch")
	assert(ip=="130.125.1.11","Expected 130.125.1.11 but was "..ip)
	--print("orion.unine.ch ->"..ip)
	
	local name,_ = socket.dns.tohostname("130.125.1.11")
	--the '.' at the end of the domain is intended by the DNS RFC
	assert(name=="orion.unine.ch.","Expected orion.unine.ch. but was "..name)	
	--print("130.125.1.11 ->"..name)

end)
