--[[
	PASTRY DHT (with enhancements) -- from the CoFeed project
	Copyright (C) 2997-2009 Lorenzo Leonini - University of Neuchâtel
	http://www.splay-project.org
--]]

--[[ BEGIN SPLAY RESSOURCES RESERVATION
END SPLAY RESSOURCES RESERVATION ]]

require"splay.base"
rpc = require"splay.rpcq"
crypto = require"crypto"
dbits = require"splay.data_bits"
evp, thread, call, time = crypto.evp, events.thread, rpc.call, misc.time

log.global_level = 2

tr, ti, sub = table.remove, table.insert, string.sub

------- part of misc
function dec_to_base(input, b)
	if input == 0 then return "0" end
	b = b or 16
	local k, out, d = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", ""
	while input > 0 do
		input, d = math.floor(input / b), math.mod(input, b) + 1
		out = string.sub(k, d, d)..out
	end
	return out
end
function base_to_dec(input, b)
	if b == 10 then return input end
	input = tostring(input):upper()
	d ={[0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
		"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"}
	local r = 0
	for i = 1, #input do
		local c = string.sub(input, i, i)
		local k
		for j = 0, #d do
			if d[j] == c then
				k = j
				break
			end
		end
		r = r * b
		r = r + k
	end
	return r
end
function convert_base(input, b1, b2)
	return dec_to_base(base_to_dec(input, b1), b2)
end

function shuffle(a)
  if #a == 1 then
    return a
  else
    return misc.random_pick(a, #a)
  end
end

----------[[ PASTRY ]]----------

-- Implementation parameters
-- key length 2^bits (max 160 because using SHA and divisible by 4)
--b, leaf_size, bits = 4, 16, 128 -- default 4, 16, 128
b, leaf_size, bits = 2, 4, 32

-- R: routing table
-- routing table is a matrix with 128/b rows and 2^b columns
-- L[i,s]: inferior and superior leaf set
-- Li sorted from greater to lower, Ls sorted from lower to greater
R, Li, Ls = {}, {}, {}

g_timeout, activity_time, check_time, ping_refresh = 60, 5, 10, 125
-- planetlab
--g_timeout, activity_time, check_time, ping_refresh = 60, 25, 20, 125

ping_c, actions, fails_count = {}, 0, 0
-- serialize insertion and reparation
insert_l, repair_l = events.lock(), events.lock()
-- protect leaf set
L_l, ping_c_l = events.lock(), events.lock()

base = 2^b
key_s = math.log(2^bits)/ math.log(base)

if key_s < base then
	print("Key size must be greater or equal than base")
	os.exit()
end

-- initialize empty lines of an empty routing table
for i = 0, key_s - 1 do R[i] = {} end

function compute_id(o)
	local id = convert_base(sub(evp.new("sha1"):digest(o), 1, bits / 4), 16, base)
	while #id < key_s do id = "0"..id end
	return id
end

function num(k)
	if k.id then k = k.id end
	return tonumber(convert_base(k, base, 10))
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
	local row = shl(key, job.me.id)
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
	if node.id == job.me.id then return true end
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
		-- OPTIMIZATION
		-- We notify the node even if not inserted
		if not notify then
			thread(function()
				local r = call(node, {'notify', job.me}, g_timeout)
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
		-- OPTIMIZATION
		-- If distance are very short it means that we are in a local test and it's
		-- better to advantage a good balance
		if r.id ~= node.id and
				((distance(r) > 0.02 and distance(node) < distance(r))
				or math.random(2) == 2) then
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
			if (not sup and misc.between_c(num(node), num(leaf[i]), num(job.me))) or
				(sup and misc.between_c(num(node), num(job.me), num(leaf[i]))) then
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
	local min, max = num(job.me), num(job.me) -- Way to put ourself in the range.
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
	local r, err = call(node, {'route', {typ = "#join#", first = 1}, job.me.id})
	if not r then return nil, err end
	-- OPTIMIZATION
	-- Useful for good balance in local tests (where ping are comparable)
	r = shuffle(r)
	for _, e in pairs(r) do
		log:info("received node "..e.id.." "..e.ip..":"..e.port)
		insert(e)
	end
	return true
end

function insert_missing(a, node)
	for _, n in pairs(a) do
		if n.id == node.id then
			return
		end
	end
	ti(a, node)
end

function try_route(msg, key, T)
	log:debug("try_route "..key)
	local msg, T, reply = forward(msg, key, T)

	local first = false
	if msg.typ == "#join#" and msg.first then
		msg.first = nil
		first = true
	end

	if not T then return reply end -- application choose to stop msg propagation
	log:debug("try_route routing "..key.." to host "..T.id.." "..T.ip..":"..T.port)
	local ok, n = rpc.a_call(T, {'route', msg, key}, g_timeout)
	if ok then
		backward(msg, key, T, n[1])
		if n[1] then
			if msg.typ == "#join#" then
				-- OPTIMIZATION
				-- If we are the 'first' node (aka rdv node), we don't give only the
				-- line in routing table corresponding to our shared prefix, but also
				-- the previous ones. So if the joining node share a prefix with us it
				-- will anyway receive a full routing table.
				local row = row_col(key)
				local start = row
				if first then start = 0 end
				for r = start, row do 
					for _, no in pairs(R[r]) do
						insert_missing(n[1], no)
					end
				end
				-- OPTIMIZATION
				insert_missing(n[1], job.me)
				-- OPTIMIZATION
				-- If we insert only ourself, 1 - 1/base nodes will have us in their
				-- routing table (because they don't begin with same prefix)
				for _, no in pairs(leafs()) do
					insert_missing(n[1], no)
				end
				return n[1] -- can be removed, avoid the unpack...
			end
			return unpack(n)
		end
	else 
		failed(T)
		log:info("cannot route through "..T.id)
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

	if key ~= job.me.id then
		if range_leaf(key) then
			-- key is within range of our leaf set
			-- route to L[i] where |key - L[i]| is minimal
			local n = nearest(key, leafs())
			if diff(n, key) < diff(job.me, key) then
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
						if diff(n, key) < diff(job.me, key) then
							return try_route(msg, key, n)
						end
					end
				end
				for _, n in pairs(leafs()) do
					if shl(n.id, key) >= row and diff(n, key) < diff(job.me, key) then
						return try_route(msg, key, n)
					end
				end
			end
		end
	end
	
	-- We are the best node for that key...
	if msg.typ == "#join#" then
		if msg.first then
			-- OPTIMIZATION
			-- see try_route()
			local nodes = {}
			for r = 0, key_s - 1 do 
				for _, n in pairs(R[r]) do
					ti(nodes, n)
				end
			end
			for _, n in pairs(leafs()) do
				insert_missing(nodes, n)
			end
			ti(nodes, job.me)
			return nodes
		else
			return {job.me, unpack(leafs())}
		end
	else
		-- By default the first returned argument is a general pastry information
		return {node = job.me, count_hops = msg.count_hops}, deliver(msg, key)
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
function forward(msg, key, T)
	if msg.typ == "#colfeed_rfi#" or msg.typ == "#colfeed_q#" then
		msg, T = transit(msg, key, T)
	end
	if T then
		if msg.hops then ti(msg.hops, job.me) end
	end
	return msg, T
end

function deliver(msg, key)
	if msg.origin then
		call(msg.origin, {'delivered', key, msg})
	end

	if msg.typ == "#colfeed_rfi#" or msg.typ == "#colfeed_q#" then
		return arrival(msg, key)
	end
end

-- Non official Pastry API (but should be :)
function backward(msg, key, T, r)
end

-------------------------- INSTRUMENTATION FUNCTIONS -----------------------

r_d = {}
function ring(m)
	if r_d[m.msg] then
		log:print("RING: "..m.msg.." already")
		call(m.origin, {'delivered', m})
	else
		r_d[m.msg] = m.msg
		log:print("RING: "..m.msg)
		m.count = m.count + 1
		if m.list then
			table.insert(m.list, job.me)
		end
		-- check leafs
		local e_c = 0
		for i, le in pairs(m.leafs) do
			if not Li[i] then break end
			if Li[i].id ~= le.id then
				e_c = e_c + 1
			end
		end
		if e_c > 0 then
			thread(function() call(m.origin, {'leaf_error', m, job.me, e_c}) end)
		end
		if Ls[1] then
			ti(m.leafs, 1, job.me)
			while #m.leafs > leaf_size / 2 do tr(m.leafs) end
			thread(function()
				if not rpc.a_call(Ls[1], {'ring', m}) then
					call(m.origin, {'next_error', m, job.me, Ls[1]})
				end
			end)
		else
			call(m.origin, {'delivered', m})
			log:print("RING: "..m.msg.." empty leaf")
			return job.me.id.."\nempty leaf"
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
			thread(function() call(job.me, m.call) end)
		end
		-- to get all the nodes in an easy way...
		if m.all then
			thread(function() call(m.origin, {'delivered', job.me}) end)
		end
		for _, n in pairs(leafs()) do
			thread(function() call(n, {'multicast', m}) end)
		end
	end
end

-------------------------- DEBUG DISPLAY -----------------------

function display_route_table()
	local out = ""
	--for i = 0, key_s - 1 do
	for i = 0, 4 do
		local str = ""..i..": "
		for c = 0, base - 1 do
			if R[i][c] then
				str = str.." "..R[i][c].id.."("..R[i][c].port..")"
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
	out = out.." ["..job.me.id.."]"
	--out = out.." ["..job.me.id.."("..num(job.me)..")]"
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
		log:print(socket.infos())
	end
	if rpc.infos then
		log:print(rpc.infos())
	end
	if events.infos then
		print(events.infos())
	end

	--log:print("_________________________________________")
	collectgarbage()
	log:print(gcinfo().." ko")
	--log:print("ME: "..job.me.id)
	log:print(display_route_table())
	log:print(display_leaf())
	--log:print("_________________________________________")
	print()
end

function shell_test(a)
	a = a or "no parameter"
	log:print(a)
	return "test ok: "..a
end

events.loop(function()

	--for i = 1, 127 do
		--print(static_id(128, i))
	--end
	--os.exit()

	local rdv = nil
	local loc = true -- local or cluster (more speed)

	if not job then -- local or rdv
		if not arg[1] then
			print("args missing")
			os.exit()
		end

		job = {me = {ip = arg[1], port = tonumber(arg[2])}}
		local rdv_ip, rdv_port = arg[3], tonumber(arg[4])

		if job.me.ip == rdv_ip and job.me.port == rdv_port then
			-- I'm the RDV
		else
			rdv = {ip = rdv_ip, port = rdv_port}
			--rdv = {ip = rdv_ip, port = math.random(20000, job.me.port - 1)}
		end

		--if arg[5] and arg[6] then
			--job.me.id = static_id(tonumber(arg[5]), tonumber(arg[6]))
		--end
		job.me.id = compute_id(job.me.ip..tostring(job.me.port))

	else -- planetlab
		loc = false
		rdv = {ip = "192.42.43.42", port = 20000}
	end
		

	if not job.me.id then
		job.me.id = compute_id(math.random(1, 1000000000)..job.me.ip..tostring(job.me.port))
	end

	log:print("ME: "..job.me.ip..":"..job.me.port.." >> "..job.me.id)

	if not rpc.server(job.me) then
		log:error("RPC bind error: "..job.me.port)
		events.sleep(5)
		os.exit()
	else
		log:print("RPC server on: "..job.me.port)
	end

	if rdv then -- we are NOT the rdv (because we have a rdv node)
		log:print("UP: "..job.me.ip..":"..job.me.port.." TRY JOINING "..rdv.ip..":"..rdv.port)

		-- wait for other nodes to come up
		if not loc then
			events.sleep(10 + job.position)
		end

		-- try to join RDV
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
				events.sleep(5)
				os.exit()
			end
		end
	end

	log:print("START: "..job.me.ip..":"..job.me.port.." >> "..job.me.id)
	events.periodic(activity_time, activity)
	events.periodic(30, debug)
	thread(check_daemon)
end)
