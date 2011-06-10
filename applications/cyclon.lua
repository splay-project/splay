--[[
	Cyclon overlay protocol implementation.

	Copyright (C) 2007 Lorenzo Leonini - University of Neuchâtel
	http://www.splay-project.org

1. Increase by one the age of all neighbors.
2. Select neighbor Q with the highest age among all neighbors, and l - 1 other random neighbors.
3. Replace Q’s entry with a new entry of age 0 and with P’s address.
4. Send the updated subset to peer Q.
5. Receive from Q a subset of no more that l of its own entries.
6. Discard entries pointing at P and entries already contained in P’s cache.
7. Update P’s cache to include all remaining entries, by firstly using empty cache slots (if any),
and secondly replacing entries among the ones sent to Q.
--]]

--[[
BEGIN SPLAY RESSOURCES RESERVATION

list_type random

END SPLAY RESSOURCES RESERVATION
--]]


require"splay.base"
rpc = require"splay.rpc"

-- GLOBAL
neighbors = job.nodes
me = job.me
shuffle_length = 5
cache_size = 20

for i, j in pairs(neighbors) do
	j.age = 0
end

function neighbors_log()
	local s = ""
	for _, n in pairs(neighbors) do
		s = s..tostring(n.ip)..":"..tostring(n.age).." "
	end
	log.write("neighbors: "..s, 5)
end

function cyclon_insert(rec_set, sent_set)
	for i, r in pairs(rec_set) do -- 6a (remove us)
		if r.ip == me.ip then
			table.remove(rec_set, i)
			break
		end
	end

	for i = #rec_set, 1 do -- 6b (remove entries already in our cache)
		for _, n in pairs(neighbors) do
			if n.ip == rec_set[i].ip then
				table.remove(rec_set, i)
				break
			end
		end
	end

	while #neighbors < cache_size and  #rec_set > 0 do -- 7a (fill cache empty slots)
		neighbors[#neighbors + 1] = table.remove(rec_set)
	end

	while #rec_set > 0 and #sent_set > 0 do -- 7b (replace sent entries)
		local t = table.remove(sent_set)
		for i, n in pairs(neighbors) do
			if n.ip == t.ip then
				neighbors[i] = table.remove(rec_set)
				break
			end
		end
	end
end

function shuffle()
	for _, n in pairs(neighbors) do -- 1 (increase age)
		n.age = n.age + 1
	end

	-- 2 (select the oldest and (shuffle_length - 1) other)
	table.sort(neighbors, function(a, b) return a.age > b.age end)
	local nei = misc.dup(neighbors)
	local selected = table.remove(nei, 1) -- oldest after the sort
	local set = misc.random_pick(nei, shuffle_length - 1)

	set[#set + 1] = {}
	set[#set].ip = me.ip -- 3 (add our address)
	set[#set].port = me.port
	set[#set].age = 0
	
	-- 4 (send the subset)
	
	local ok, r = rpc.a_call(selected, {"receive_set", set})
	if ok then
		table.remove(set)
		cyclon_insert(r[1], set) -- 6 - 7
	else
		log.error("ERROR receiving from "..selected.ip..":"..selected.port.." : "..r)
	end
end

function receive_set(rec_set)
	local set = misc.random_pick(neighbors, shuffle_length)
	cyclon_insert(rec_set, set)
	neighbors_log()
	return set
end

-- main
events.thread(function()
	if not rpc.server(me.port, 24) then
		log.error("Bind error: "..me.port)
		return
	end
	events.sleep(20) -- Intial sleep time to let other peers run.
	events.periodic(20, shuffle)
	events.periodic(20, neighbors_log)
end)

events.run()
