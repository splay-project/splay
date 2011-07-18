--[[
       Splay Client Commands ### v1.1 ###
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

-- SPLAYschool tutorial

-- BASE libraries (threads, events, sockets, ...)
require"splay.base"
distdb = require"splay.distdb"

events.loop(function()
	distdb.init()
	--[[
	distdb.put("3", 6)
	distdb.put("hello", "10")
	a = distdb.get("3")
	b = distdb.get("hello")
	print(a,b)]]
end)

-- now, you can watch the logs of your job and enjoy ;-)
-- try this job with multiple splayds and different parameters

