--[[
	Lua Pastry Protocol Implementation
	Copyright (C) 2007-2008 Lorenzo Leonini - University of Neuchâtel
	http://www.splay-project.org
--]]

--[[
NOTES:

This is the 'paper' implementation, supporting only base 16 (b = 4). There is
a more optimized version in 'colfeed'.
--]]

--[[ BEGIN SPLAY RESSOURCES RESERVATION
END SPLAY RESSOURCES RESERVATION ]]


require"splay.base"
rpc = require"splay.rpc"
crypto = require"crypto"
evp, thread, call, time = crypto.evp, events.thread, rpc.call, misc.time

log.global_level = 1

tr, ti, sub = table.remove, table.insert, string.sub

-- Implementation parameters
-- key length 2^bits (max 160 because using SHA and divisible by 4)
b, leaf_size, bits = 4, 16, 128 -- default 4, 16, 128

-- A: us, R: routing table, L[i,s]: inferior and superior leaf set
-- Li sorted from greater to lower, Ls sorted from lower to greater
A, R, Li, Ls = {}, {}, {}, {}

g_timeout, activity_time, check_time, ping_refresh = 60, 5, 10, 125
-- planetlab
--g_timeout, activity_time, check_time, ping_refresh = 60, 25, 20, 125

ping_c, actions, fails_count = {}, 0, 0
-- serialize insertion and reparation
insert_l, repair_l = events.lock(), events.lock()
-- protect leaf set
L_l, ping_c_l = events.lock(), events.lock()

key_s = math.log(2^bits)/ math.log(2^b)

if key_s < 2^b then
	print("Key size must be greater or equal than base")
	os.exit()
end
if b ~= 4 then
	print("b must be 4, because base 16 (hexadecimal) is needed in one function.")
	os.exit()
end

-- initialize empty lines of an empty routing table
for i = 0, key_s - 1 do R[i] = {} end

function compute_id(o) return sub(evp.new("sha1"):digest(o), 1, bits / 4) end
function num(k) -- Hex dependant
	if k.id then return tonumber("0x"..k.id) else return tonumber("0x"..k) end
end 
function diff(key1, key2)
	local k1, k2, a, b = num(key1), num(key2)
	if k1 < k2 then a, b = k2, k1 else a, b = k1, k2 end
	return math.min(a - b, 2^bits - a + b)
end

-- return the length of the shared prefix
function shl(a, b)
	for i = 1, key_s do
		if sub(a, i, i) ~= sub(b, i, i) then return i - 1 end
	end
	return key_s
end

function row_col(key)
	local row = shl(key, A.id)
	return row, num(sub(key, row + 1, row + 1))
end

-- calculate our distance from a node
-- in this implementation distance = ping time
function ping(n, no_c)
	ping_c_l:lock()
	if not (not no_c and ping_c[n.id] and ping_c[n.id].last > time() - ping_refresh) then
		log:debug("ping "..n.id)
		local t = time()
		if rpc.ping(n, g_timeout) then
			ping_c[n.id] = {last = time(), value = true, time = time() - t}
		else
			ping_c[n.id] = {last = time(), value = false, time = math.huge}
			failed(n)
		end
	end
	local v, t = ping_c[n.id].value, ping_c[n.id].time
	ping_c_l:unlock()
	return v, t
end

-- Function called in insert_route() only, ping IS always cached.
function distance(n)
	log:debug("distance "..n.id)
	local v, t = ping(n)
	return t
end

function already_in(node)
	-- we could check that a node in the leafset could eventually goes in the
	-- routing table later, but not useful at the routing level
	if node.id == A.id then return true end
	for _, n in pairs(leafs()) do
		if n.id == node.id then return true end
	end
	if range_leaf(node.id) then return false end
	for r = 0, key_s - 1 do
		for c = 0, key_s - 1 do
			if R[r][c] and R[r][c].id == node.id then
				return true
			end
		end
	end
end

-- Entry point when we receive a new node
-- ok: to avoid notify a node that just notify us (and some pings too)
function insert(node, notify) thread(function() insert_t(node, notify) end) end
function insert_t(node, notify)
	insert_l:lock()
	if already_in(node) or (not notify and not ping(node)) then
		log:debug("do not insert "..node.id)
	else
		log:debug("insert "..node.id)
		-- these inserts require NO network operations
		local r1, r2 = insert_leaf(node), insert_route(node)
		if (r1 or r2) and not notify then
			thread(function()
				local r = call(node, {'notify', A}, g_timeout)
				if r then return true else failed(node) end
			end)
		end
	end
	insert_l:unlock()
end

function insert_route(node)
	log:debug("insert_route "..node.id)
	local row, col = row_col(node.id)
	local r = R[row][col]
	log:debug("   at pos "..row..":"..col)
	-- if the slot is empty, or there is another node that is more distant
	-- => we put the new node in the routing table
	if not r then
		log:debug("   empty => OK")
		R[row][col] = node
		return true
	else
		log:debug("   already "..r.id)
		if r.id ~= node.id and distance(node) < distance(r) then
			log:debug("   OK")
			R[row][col] = node
			return true
		else
			log:debug("   NOT OK")
			return false
		end
	end
end

function insert_leaf(node)
	L_l:lock()
	log:debug("insert_leaf "..node.id)
	local r1, r2 = iol(node, Li, false), iol(node, Ls, true)
	L_l:unlock()
	return r1 or r2
end

-- insert_one_leaf
function iol(node, leaf, sup)
	for i = 1, leaf_size / 2 do
		if leaf[i] then
			if node.id == leaf[i].id then break end
			if (not sup and misc.between_c(num(node), num(leaf[i]), num(A))) or
				(sup and misc.between_c(num(node), num(A), num(leaf[i]))) then
				ti(leaf, i, node)
				while #leaf > leaf_size / 2 do tr(leaf) end
				log:debug("    leaf inserted "..node.id.." at pos "..i)
				return i
			end
		else
			leaf[i] = node
			log:debug("    leaf inserted "..node.id.." at pos "..i)
			return i
		end
	end
	return false
end

-- leaf inf and sup mixed with each elements only once
function leafs()
	L_l:lock()
	local L = misc.dup(Li)
	for _, e in pairs(Ls) do
		local found = false
		for _, e2 in pairs(Li) do
			if e.id == e2.id then found = true break end
		end
		if not found then L[#L + 1] = e end
	end
	L_l:unlock()
	return L
end

function range_leaf(D) -- including ourself in the range
	local min, max = num(A), num(A) -- Way to put ourself in the range.
	L_l:lock()
	if #Li > 0 then min = num(Li[#Li]) end
	if #Ls > 0 then max = num(Ls[#Ls]) end
	L_l:unlock()
	return misc.between_c(num(D), min - 1, max + 1)
end

function nearest(D, nodes)
	log:debug("nearest "..D)
	local d, j = math.huge, nil
  for i, n in pairs(nodes) do
		if diff(D, n) < d then
			d = diff(D, n)
			j = i
		end
	end
	return nodes[j]
end

function repair(row, col, id)
	repair_l:lock()
	if not R[row][col] then -- already repaired...
		log:debug("repair "..row.." "..col)
		-- We only contact node that have the same prefix as us at least until the
		-- row of the failed node. That means if we ask this kind of node a
		-- replacement for the failed node at that position, it will give us a node
		-- that fit too in our routing table.
		local r = row
		while r <= key_s - 1 and not rfr(r, row, col, id) do r = r + 1 end
	end
	repair_l:unlock()
end

-- Use row 'r' to contact a node that could give us a replacement for the node
-- at pos (row; col)
-- id: to avoid re-inserting the same failed node
-- TODO we could first check if a replacement is not available in the leafset
function rfr(r, row, col, id) -- repair from row
--	log:debug("rfr "..r.." "..row.." "..col.." "..id)
	for c, node in pairs(R[r]) do
		if c ~= col then
			local ok, r = rpc.a_call(node, {'get_node', row, col}, g_timeout)
			-- We verify that to no accept the same broken node than before.
			if ok then
				r = r[1]
				if r and r.id ~= id then
					-- We REALLY ping this node now
					if ping(r, true) then
						insert(r)
						log:info("Node repaired with "..r.id.." "..r.ip..":"..r.port)
						return true
					end
				end
			else
				failed(node)
			end
		end
	end
end

function failed(node) thread(function() failed_t(node) end) end
function failed_t(node)
	log:debug("failed "..node.id.." "..node.ip..":"..node.port)
	-- update cache
	ping_c_l:lock()
	ping_c[node.id] = {last = time(), value = false, time = math.huge}
	ping_c_l:unlock()
	-- clean leafs
	L_l:lock()
	for i, n in pairs(Li) do if node.id == n.id then tr(Li, i) end end
	for i, n in pairs(Ls) do if node.id == n.id then tr(Ls, i) end end
	L_l:unlock()
	local row, col = row_col(node.id)
	if R[row][col] and R[row][col].id == node.id then
		R[row][col] = nil
		repair(row, col, node.id)
	end
end

-- local, we want to join "node"
-- we have not its id, we can't add it !
function join(node)
	log:debug("join "..node.ip..":"..node.port)
	local r, err = call(node, {'route', {typ = "#join#"}, A.id})
	if not r then return nil, err end
	for _, e in pairs(r) do
		if e.id then
			log:debug("received node "..e.id.." "..e.ip..":"..e.port)
			insert(e)
		end
	end
	return true
end

function try_route(msg, key, T)
	log:debug("try_route "..key)
	local msg, T, reply = forward(msg, key, T)

	if not T then return reply end -- application choose to stop msg propagation
	log:debug("try_route routing "..key.." to host "..T.id.." "..T.ip..":"..T.port)
	local ok, n = rpc.a_call(T, {'route', msg, key}, g_timeout)
	if ok then
		if n[1] then
			if msg.typ == "#join#" then
				local row, col = row_col(key)
				for _, node in pairs(R[row]) do
					local found = false
					for _, j in pairs(n[1]) do
						if j.id == node.id then
							found = true
							break
						end
					end
					if not found then
						ti(n[1], node)
					end
				end
			end
			return unpack(n)
		else
			return nil
		end
	else 
		failed(T)
		log:info("cannot route through "..T.id)
		-- before, wa always reply somebody (us at the very end...)
		--return route(msg, key)
	end
end

function route(msg, key, no_count_action) -- Pastry API
	log:debug("route "..key.." "..tostring(msg.typ))
	if not no_count_action then actions = actions + 1 end

	-- Security
	if not msg.count_hops then msg.count_hops = 0 end
	msg.count_hops = msg.count_hops + 1
	if msg.count_hops > 15 then
		log:warn("Problem routing "..key.." max hops reached")
		return nil, "routing problem max hops reached: "..key
	end

	-- good only if try_route halt on error...
	if msg.typ == "#test#" then
		if not msg.count then msg.count = 0 else msg.count = msg.count + 1 end
		if not msg.trace then msg.trace = "" end
		if not msg.hops then msg.hops = {A} else ti(msg.hops, A) end
	end

	if key ~= A.id then --VS job.me => A
		if range_leaf(key) then
			-- key is within range of our leaf set
			-- route to L[i] where |key - L[i]| is minimal
			local n = nearest(key, leafs())
			if diff(n, key) < diff(A, key) then --VS job.me => A
				return try_route(msg, key, n)
			end
		else
			-- use the routing table
			-- the message is forwarded to a node that shares a common prefix with the
			-- key by at least one more digit
			local row, col = row_col(key)
			if R[row][col] then
				return try_route(msg, key, R[row][col])
			else
				-- rare case
				-- If we find a node that match criterias, we take it. We don't
				-- search for the best one.
				-- since we begin at the row l, all the nodes will have a prefix >= l
				for r = row, key_s - 1 do 
					for _, n in pairs(R[r]) do
						if diff(n, key) < diff(A, key) then  --job.me => A
							return try_route(msg, key, n)
						end
					end
				end
				for _, n in pairs(leafs()) do
					if shl(n.id, key) >= row and diff(n, key) < diff(A, key) then --job.me => A
						return try_route(msg, key, n)
					end
				end
			end
		end
	end
	
	-- We are the best node for that key...
	if msg.typ == "#join#"
		then return {A, unpack(leafs())}
	else
		return A, deliver(msg, key)
	end
end

-- if no activity, create artificial one to detect route failures
function activity()
	log:debug("activity")
	if actions == 0 then
		local key = compute_id(math.random(1, 1000000000))
		log:debug("activity msg: "..key)
		thread(function() route({typ = "#activity#"}, key, true) end)
	end
	actions = 0
end

function do_leaf(node)
	local r = call(node, 'leafs', g_timeout)
	if r then
		log:debug("check receive "..#r.." leafs")
		for _, n in pairs(r) do insert(n) end
	else
		failed(node)
	end
end

function check_daemon()
	local pos = 1
	while events.sleep(check_time) do
		log:debug("check daemon")
		local L = leafs()
		if pos < #L then pos = pos + 1 else pos = 1 end
		-- case where leaf set is empty
		if L[pos] then do_leaf(L[pos]) end
	end
end

-- RPC aliases
function get_node(row, col) return R[row][col] end
function notify(node) insert(node, true) return true end

-- Pastry API
function send(msg, node) return call(node, {'route', msg, node.id}) end

-- Pastry API (must override)
function forward(msg, key, T) return msg, T end
function deliver(msg, key)
	if msg.typ == "#test#" and msg.origin then
		call(msg.origin, {'delivered', key, msg})
	end
	--[[add here code to handle Scribe messages..]]
end

-------------------------- INSTRUMENTATION FUNCTIONS -----------------------

function randomize(value, percent)
	local e = value * percent
	return math.random((value - e) * 1000, (value + e) * 1000) / 1000
end

-- START Query Generator - for benchmarks

-- store queries
queries = {}
q_interval = nil

-- The interval value try to express a value for q/s removing the time of the
-- previous query from the sleep time. But the real sleep time will always be
-- bigger than the expected time (depend of the scheduler). But there is no way
-- to fix that except than trying to do some statistical analysis of the
-- average delays of the sheduler.

-- number of threads that do queries
-- interval between 2 queries (for each thread)
-- max_queries (by thread)
function do_query(number, interval, max_queries)
	max_queries = max_queries or math.huge
	number = number or 1
	q_interval = interval
	for i = 1, number do
		thread(function()
			-- randomize start
			if q_interval then -- with randomization
				events.sleep(math.random(0, q_interval * 1000) / 1000)
			end
			local c = 0
			while c < max_queries do
				c = c + 1
				local key = compute_id(math.random(1, 1000000000))
				local msg = {
					typ = "#test#",
					origin = {ip = A.ip, port = A.port}
				}
				queries[key] = {}
				local start_time = misc.time()
				queries[key].start_time = start_time
				local s = route(msg, key)
				local end_time = misc.time()
				if queries[key] then -- maybe we have flushed the results...
					queries[key].reply = end_time - start_time
					queries[key].status = s
				end
				if q_interval then
					local diff = end_time - start_time
					if q_interval - diff > 0 then
						events.sleep(randomize(q_interval - diff, 0.05))
					end
				end
			end
		end)
	end
end

function do_query_etienne(num_host_nodes)
	local max_queries = 50
	q_interval = (num_host_nodes / 3 * 230) / 1000

	-- randomize start
	events.sleep(math.random(0, q_interval * 1000) / 1000)

	local c = 0
	while c < max_queries do
		c = c + 1
		local key = compute_id(math.random(1, 1000000000))
		local msg = {
			typ = "#test#",
			origin = {ip = A.ip, port = A.port}
		}
		queries[key] = {}
		local start_time = misc.time()
		queries[key].start_time = start_time
		local s = route(msg, key)
		local end_time = misc.time()
		if queries[key] then -- maybe we have flushed the results...
			queries[key].reply = end_time - start_time
			queries[key].status = s
		end
		if q_interval then
			local diff = end_time - start_time
			if q_interval - diff > 0 then
				events.sleep(randomize(q_interval - diff, 0.05))
			end
		end
	end
	queries_stats()
	log:print("END OF TEST")
	events.sleep((5 * q_interval) + 10)
	os.exit()
end

function delivered(key, msg)
	if queries[key] then
		queries[key].deliver = misc.time() - queries[key].start_time
		queries[key].hops = #msg.hops - 1
	end
end

function queries_stats()
	for _, q in pairs(queries) do
		if q.deliver then
			log:print("QUERY "..q.hops.." "..q.deliver.." "..q.start_time)
		else
			log:print("FAILED "..q.start_time)
		end
	end
	queries = {}
end

function set_interval(val)
	q_interval = val
end

function delete_queries()
	queries = {}
end

-- END Query Generator - for benchmarks

function kill()
	log:print("KILL in 10s ")
	events.sleep(10)
	os.exit()
end

r_d = {}
function ring(m)
	if r_d[m.msg] then
		log:print("RING: "..m.msg.." already")
		call(m.origin, {'delivered', m})
	else
		r_d[m.msg] = m.msg
		log:print("RING: "..m.msg)
		m.count = m.count + 1
		-- check leafs
		local e_c = 0
		for i, le in pairs(m.leafs) do
			if not Li[i] then break end
			if Li[i].id ~= le.id then
				e_c = e_c + 1
			end
		end
		if e_c > 0 then
			thread(function() call(m.origin, {'leaf_error', m, A, e_c}) end)
		end
		if Ls[1] then
			ti(m.leafs, 1, A)
			while #m.leafs > leaf_size / 2 do tr(m.leafs) end
			thread(function()
				if not rpc.a_call(Ls[1], {'ring', m}) then
					call(m.origin, {'next_error', m, A, Ls[1]})
				end
			end)
		else
			call(m.origin, {'delivered', m})
			log:print("RING: "..m.msg.." empty leaf")
			return A.id.."\nempty leaf"
		end
	end
end

m_d = {}
function multicast(m)
	if not m_d[m.msg] then
		m_d[m.msg] = m.msg
		log:print("MULTICAST: "..m.msg)
		-- call for ourself !!!
		if m.call then
			log:print("calling "..m.call[1])
			thread(function() call(A, m.call) end)
		end
		-- to get all the nodes in an easy way...
		if m.all then
			thread(function() call(m.origin, {'delivered', A}) end)
		end
		for _, n in pairs(leafs()) do
			thread(function() call(n, {'multicast', m}) end)
		end
	end
end

--all_d = {}
--function all(m)
	--if not all_d[m.msg] then
		--all_d[m.msg] = m.msg
		--for _, n in pairs(leafs()) do
			--thread(function() call(n, {'all', m}) end)
		--end
		--thread(function() call(m.origin, {'delivered', A}) end)
	--end
--end

function display_route_table()
	local out = ""
	--for i = 0, key_s - 1 do
	for i = 0, key_s / 4 do
		local str = ""..i..": "
		for c = 0, 2^b - 1 do
			if R[i][c] then
				str = str.." "..R[i][c].id
			else
				str = str.." -"
			end
		end
		out = out..str.."\n"
	end
	return out
end

function display_leaf()
	local out = ""
	for i = #Li, 1, -1 do
		if Li[i] then
			out = out.." "..Li[i].id
			--out = out.." "..Li[i].id.."("..num(Li[i])..")"
		end
	end
	out = out.." ["..A.id.."]"
	--out = out.." ["..A.id.."("..num(A)..")]"
	for i = 1, #Ls do
		if Ls[i] then
			out = out.." "..Ls[i].id
			--out = out.." "..Ls[i].id.."("..num(Ls[i])..")"
		end
	end
	return out
end

function socket_stats()
	if socket.stats then
		return socket.stats()
	end
end

function debug()
	if socket.infos then
		socket.infos()
	end
	if events.stats then
		print(events.stats())
	end

	log:print("_________________________________________")
	collectgarbage()
	log:print(gcinfo().." ko")
	log:print("ME: "..A.id)
	log:print(display_route_table())
	log:print(display_leaf())
	log:print("_________________________________________")
	print()
end

function shell_test(a)
	a = a or "no parameter"
	log:print(a)
	return "test ok: "..a
end

------------------------------------------------------------------

function run()
	A.id = compute_id(math.random(1, 1000000000)..A.ip..tostring(A.port))

	if not rpc.server(A.port, 24) then
		log:error("RPC bind error: "..A.port)
		return
	end
	log:print("UP: "..A.ip..":"..A.port)

	if job then
		-- wait others to come up
		local time = job.position
		events.sleep(10 + time / 2)

		local try = 0
		local ok, err = join(rdv)
		while not ok do
			try = try + 1
			if try <= 3 then
				log:print("Cannot join "..rdv.ip..":"..rdv.port..": "..tostring(err).." => try again")
				events.sleep(math.random(try * 30, try * 60))
				ok, err = join(rdv)
			else
				log:print("Cannot join "..rdv.ip..":"..rdv.port..": "..tostring(err).."  => end")
				os.exit()
			end
		end
	else
		if rdv then
			local try = 0
			local ok, err = join(rdv)
			while not ok do
				try = try + 1
				if try <= 3 then
					log:print("Cannot join: "..tostring(err).." => try again")
					events.sleep(math.random(try * 30, try * 60))
					ok, err = join(rdv)
				else
					log:print("Cannot join: "..tostring(err).."  => end")
					os.exit()
				end
			end
		else
			log:print("RDV node")
		end
	end

	log:print("START: "..A.id)

	events.periodic(activity_time, activity)
	events.periodic(30, debug)
	thread(function() check_daemon() end)
	--events.sleep(60)
	--do_query(1, 10)
end

if job then
	A = job.me
	--rdv = {ip = "192.42.43.42", port = 20000}
	--rdv = {ip = "127.0.0.1", port = 20000}
	rdv = job.nodes[1]
else
	A.ip = "127.0.0.1"
	A.port = 20000
	if #arg == 1 then -- exclusivly for local testing
		rdv = {ip = "127.0.0.1", port = 20000}
		A.port = 20000 + tonumber(arg[1])
	elseif #arg == 2 then -- rdv point on a network
		A = {ip = arg[1], port = tonumber(arg[2])}
	elseif #arg == 4 then
		A = {ip = arg[1], port = tonumber(arg[2])}
		rdv = {ip = arg[3], port = tonumber(arg[4])}
	end
end

-- NAT support for 10.0.0.0/8 IPs
if string.sub(A.ip, 1, 3) ~= "10." then -- we are external to the nat
	-- a_call, the low level rpc call, we will override it to support ip changes
	rpc.a_call_ori = rpc.a_call
	rpc.a_call = function(n, ...)
		local node = misc.dup(n)
		if type(node) == "table" and string.sub(node.ip, 1, 3) == "10." then
			node.ip = "192.42.43.30" -- gateway for 10.0.0.0/8 IPs
		elseif type(node) == "string" and string.sub(node, 1, 3) == "10." then
			node = "192.42.43.30" -- gateway for 10.0.0.0/8 IPs
		end
		return rpc.a_call_ori(node, unpack(arg))
	end
end

thread(run)
events.loop()
