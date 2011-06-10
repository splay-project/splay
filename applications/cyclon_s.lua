--[[
	Cyclon overlay protocol implementation.

	Copyright (C) 2007 Lorenzo Leonini - University of Neuchâtel
	http://www.splay-project.org

1. Increase by one the age of all neighbours.
2. Select neighbor Q with the highest age among all neighbours, and l - 1 other random neighbours.
3. Replace Q’s entry with a new entry of age 0 and with P’s address.
4. Send the updated subset to peer Q.
5. Receive from Q a subset of no more that l of its own entries.
6. Discard entries pointing at P and entries already contained in P’s cache.
7. Update P’s cache to include all remaining entries, by
	firstly using empty cache slots (if any),
	and secondly replacing entries among the ones sent to Q.
--]]

--[[
BEGIN SPLAY RESSOURCES RESERVATION

list_type random
list_size 20

END SPLAY RESSOURCES RESERVATION
--]]

require"splay.base"
rpc = require"splay.rpc"

shuffle_length, cache_size, shuffle_time, rpc_timeout = 5, 20, 20, 15

neighbours = job.nodes
for _, n in pairs(neighbours) do n.age = 0 end

function neighbours_log()
	table.sort(neighbours, function(a, b) return a.age > b.age end)
	local s = ""
	for _, n in pairs(neighbours) do
		s = s..n.ip..":"..n.port.." ("..n.age..") "
	end
	log:print("neighbours: "..s)
end

function cyclon_insert(rec_set, sent_set)
	sent_set = misc.dup(sent_set)
	for i, r in pairs(rec_set) do -- 6a: remove us
		if r.ip == job.me.ip and r.port == job.me.port then
			table.remove(rec_set, i)
			break
		end
	end

	if #rec_set > 0 then -- 6b: remove entries (or rec_set) already in our cache
		for i = #rec_set, 1 do
			for _, n in pairs(neighbours) do
				if n.ip == rec_set[i].ip and n.port == rec_set[i].port then
					table.remove(rec_set, i)
					break
				end
			end
		end
	end

	while #neighbours < cache_size and #rec_set > 0 do -- 7a: fill cache empty slots
		neighbours[#neighbours + 1] = table.remove(rec_set)
	end

	while #rec_set > 0 and #sent_set > 0 do -- 7b: replace sent entries
		local t = table.remove(sent_set)
		for i, n in pairs(neighbours) do
			if n.ip == t.ip and n.port == t.port then
				neighbours[i] = table.remove(rec_set)
				break
			end
		end
	end
	neighbours_log()
end

function shuffle()
	-- 1: increase age
	for _, n in pairs(neighbours) do n.age = n.age + 1 end

	-- 2: select the oldest and (shuffle_length - 1) others
	table.sort(neighbours, function(a, b) return a.age > b.age end)
	local selected = table.remove(neighbours, 1) -- oldest after the sort
	local sent_set = misc.random_pick(neighbours, shuffle_length - 1)

	-- 3: add our address
	sent_set[#sent_set + 1] = {ip = job.me.ip, port = job.me.port, age = 0}
	
	-- 4: send the subset
	local ok, r = rpc.a_call(selected, {"receive_set", sent_set}, rpc_timeout)
	if ok then
		table.remove(sent_set)
		cyclon_insert(r[1], sent_set) -- 6 & 7
	else
		log:error("ERROR receiving from "..selected.ip..":"..selected.port.." : "..r)
	end
end

function receive_set(rec_set)
	local sent_set = misc.random_pick(neighbours, shuffle_length)
	cyclon_insert(rec_set, sent_set)
	return sent_set
end

events.loop(function()
	if not rpc.server(job.me) then
		log:error("Bind error: "..job.me.port)
		return
	end
	events.sleep(20) -- Intial sleep time to let other peers run.
	events.thread(shuffle)
	events.periodic(shuffle, shuffle_time)
end)
