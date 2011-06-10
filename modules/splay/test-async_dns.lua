--[[
       Splay ### v1.0.1 ###
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

require"splay.base"
async_dns=require"async_dns"
events.run(function()
	--test module
	local ip,full_ris = async_dns.toip("yahoo.it")
	assert(ip)
	local name,full_ris = async_dns.tohostname("209.191.122.70")
	assert(name=="ir1.fp.vip.mud.yahoo.com.")
	assert(full_ris)
	
	--re-do the same query to test caching..
	local ip,full_ris = async_dns.toip("yahoo.it")
	assert(ip)
	local name,full_ris = async_dns.tohostname("209.191.122.70")
	assert(name=="ir1.fp.vip.mud.yahoo.com.")
	assert(full_ris)
	
	
	--test for separate instance 
    local dns=assert(async_dns.resolver()) 
	local ip,full_ris = dns:toip("yahoo.it")
	assert(ip~="")
	
	assert(full_ris)
	local name,full_ris = dns:tohostname("209.191.122.70")
	assert(name=="ir1.fp.vip.mud.yahoo.com.")
	assert(full_ris)
	
end)


