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
local crypto = require"crypto"
local rpc = require"splay.rpc"

events.loop(function()
	math.randomseed(os.time())
	distdb.init(job)
	--[[
	distdb.put("3", 6)
	distdb.put("hello", "10")
	a = distdb.get("3")
	b = distdb.get("hello")
	print(a,b)]]
	if job.position == 1 then
		for i=1,10 do
			local key = crypto.evp.digest("sha1",math.random(100000))
			local re_key = crypto.evp.digest("sha1",math.random(100000))
			log:print("Key is "..key)
			local master = distdb.get_master(key)
			log:print("Master is "..master.id)
				if math.random(5) == 1 then
					master = distdb.get_master(re_key)
					log:print("Master changed to "..master.id)
				end
			log:print()
			local answer = rpc.call(master, {"distdb.put", key, 1})
			log:print("")
			log:print("put successfully done? ", answer)
			log:print("")
			events.sleep(5)
		end
	end
end)

-- now, you can watch the logs of your job and enjoy ;-)
-- try this job with multiple splayds and different parameters

