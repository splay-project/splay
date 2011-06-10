--[[
	SPLAY Web Cache (on Pastry DHT)
	Copyright (C) 2008 Lorenzo Leonini - University of Neuchâtel
	http://www.splay-project.org
--]]

--[[
NOTES:

A node is a triplet {id (key), ip, port} like stored in A or in routing
and leaf tables.

In our implementation, when we do routing, the first returned argument is a
general information array (containing for example target node and number
of hops).

To repair, we use activity(). If we have not received a routing message for a
given time, we will generate a random message to route. And we activly check our
leafs by asking them their leafset and maybe finding new nodes.

With less than 17 nodes (if the leaf set has a size of 16), some nodes will be
twice and some other will miss (the between() function will not understand the
fact that we will use all the circle). In there rare cases, a function like
ring() will miss some nodes. Although, routing is not affected and if the number
of nodes grow, all will work as expected again.

R (routing table) does not require extra locking because we work each time with
one element at a defined position and the operation to set/replace/remove that
element are atomics.

If slow nodes are during a short moment heavily loaded, they could timeout with
everybody connected to them. So, nobody will know them anymore. So, even if they
have some people on their leafset, no other have them in their. So they will not
come back activly in the network. We could fix that: when we receive a leaf
request (a node check his leafset), we should try to insert the node doing the
request.

TODO
- When a node is lost, it can leave an empty space in routing table, in leafset or
	both. We should check if there is a replacement in leafset for the routing table
	and vice versa. already_in() can in some case, generate a new insert() that
	could have been avoided if leafset and routing table were well synchronized.

--]]

--[[ BEGIN SPLAY RESSOURCES RESERVATION

network_max_sockets 64
network_nb_ports 2
max_time 864000
max_mem 6291456
disk_max_size 268435456
disk_max_files 8192
disk_max_file_descriptors 64

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

-------------------------- CRFS UTILS -----------------------

--[[
Compute the rate 'evolutive average' based on 'max_sample' samples for a
variable.

This function needs to be called at a regular interval. The average will be
computed on 'time_between_call * max_sample' period.
--]]
_c_r = {}
_c_r_last = {}

-- Diff mode: if v always increase and isn't reset
function compute_rate(name, v, max_sample, diff)
  max_sample = max_sample or 10
	if diff == nil then
		diff = true
		if max_sample < 2 then max_sample = 2 end
	end

  if not _c_r[name] then
		if diff then
			_c_r[name] = {0}
		else
			_c_r[name] = {}
		end
	end

  table.insert(_c_r[name], 1, v)
  if #_c_r[name] > max_sample then table.remove(_c_r[name]) end

  local tot = 0
  local num = 0

	-- In diff mode we have an additionnal fake sample for init.
	local s = #_c_r[name]
	if diff then s = s - 1 end

  for i = 1, s do
		local lv = _c_r[name][i]
		if diff then lv = _c_r[name][i] - _c_r[name][i + 1] end
		tot = tot + lv * ((s + 1 - i) / s)
    num = num + i
  end

	_c_r_last[name] = tot * (s / num)
--print(">>>>>>", name, v, "=>", _c_r_last[name])
	return _c_r_last[name]
end

function rate(name)
	if not _c_r_last[name] then
		return 0
	else
		return _c_r_last[name]
	end
end

-- Keep the n highest rates (can keep a little more because that function try to
-- be efficient :-)
function keep_top_rates(n)
	local a = {}
	for k, v in pairs(_c_r_last) do
		table.insert(a, v)
	end
	table.sort(a)
	-- nth element has a rate of l (limit), we will remove all elements that have
	-- a slower rate (but other elements can have too a rate l and will be kept)
	local l = a[n]
	for k, v in pairs(_c_r_last) do
		if v < l then
			_c_r_last[v] = nil
			_c_r[v] = nil
		end
	end
end

-- Bloom filter functions for similarities

bf_k = 10
function estimated_size(bs)
	local s = string.len(bs) * 8
	local z = s - dbits.cardinality(bs)
	return math.floor((math.log(z / s) / math.log(1 - 1 / s) / bf_k) + 0.5)
end

function estimated_union(bs1, bs2)
	return estimated_size(dbits.dor(bs1, bs2))
end

function estimated_intersection(bs1, bs2)
	local s1, s2 = string.len(bs1) * 8, string.len(bs2) * 8
	local z1, z2 = s1 - dbits.cardinality(bs1), s2 - dbits.cardinality(bs2)
	local inner_product = dbits.dand(bs1, bs2)
	local z12 = string.len(inner_product) * 8 - dbits.cardinality(inner_product)
	local z = (z1 + z2 - z12) / (z1 * z2)
	return math.floor((-math.log(z * s1) / math.log(1 - 1 / s1) / bf_k) + 0.5)
end

function sim_jaccard(bs1, bs2)
	local union = estimated_union(bs1, bs2)
	if union == 0 then return 0 end
	return estimated_intersection(bs1, bs2) / union
end

-------------------------- CRFS -----------------------

--[[
-- COLFEED

##### Meeting EPFL

Personal notes:
	Queue is a way to determine popularity of an item.

	Queue, POPStore and Archive are for EACH query (query = 1 node).


What are similars RFitems ? Can be similar (Q, D, DP) or
(Q, D, DP, UP)... DP can be computed using user profile too... The problem if
we include UP in that computation we will probably have most RFitems not
similars... So we will only use (Q, D) to consider items similars.

(Q, D):	U(DPi), t_last, rate_max, rate_current, (rate_hist_k)*
				snippet, number_replies

Q => (Q, D)
D => (Q, D)

(rates are rate / overall rate for the physical node at that moment of
computation)

Each dt, we update all rates. When a new RFitem is inserted it has
rate_max = 1 and rate_current = 1.

Each dt2 (multiple of dt and synchronized after a dt), we execute cleaning.
Cleaning will be skipped if the amount of space is sufficient.

When space is needed:

	1) freshness (threshold, RFitems)
		If t_last < now() - max_age, we remove the RFitem.
		This filter will be applied at regular intervals even if we doesn't
		reach a memory limit.

	2) popularity (threshold, RFitems)
		if max_rate < threshold_popularity, this item is not popular and can be
		removed.

	2 alt) popularity (threshold, RFitems)
		We order RFitems by number of receptions. We delete (in order) those
		that have been received less than X times (threshold_popularity).
		We don't discuss about this one, but I think it can replace filter 2,
		because lots of items that have been received only once or twice are
		not "rated" (N/A because of insufficient samples) or their rate /
		max_rate are not relevant.

	3a) similarities (Order, Q)
		Remove the less relevant/most redondant RFitems based on computations
		that needs to be defined. Probably depending of Q to group elements
		because a full comparison is too expensive. Probably we want to try to
		keep a minimal set of documents for each query Q.
		Actually disabled.

	3b) usefulness (Order, Q)
		If Q link to a set of RFitems, some of them are never retrieved.
		Remove those that are nevers used (after a certain amount of time) to
		answer queries.
		Actually disabled.

	4) Order all (RFitems)
		- Order by max_rate
		- (if equal) order by current_rate
		- (if equal) oder by t_last
		- Remove the last elements
		- Will probably be replaced by filtering(s) of level 3 when they are ready.

If we are over a maximal limit of space, the new RFitems we receive will
simply not be inserted (if the RFitem NOT exists, if it exists, its values
will be updated).

What will be the approximate size of DP in this architecture ?

How many time for dt, dt2 ? If we choose dt too small, all the rates will be
0 or 1... For that, I agree that Queue was a more appropriate choice...

So I propose to use this structure instead of the previous:

(Q, D): U(DPi), t_last, rate_max, queue (X last RFi arrival times)
				snippet, number_replies

- For each (Q, D), the node will store the time of X last items (the queue).
	- rates will be updated each time an item is inserted into the queue
			If the queue has more than Y items, we update rates:
				rate = number_of_elements / now() - t_min
				(can be replaced by a more complex formula)
			If the queue has less than Y items, (Q, D) is still
			"en periode de test" and rates will be N/A. But, if the item is
			too slow, it will anyway be cleaned by cleaning #1.
	- filters above needs no changes
	- faster to update
	- use a little more space, but not a lot
	- we don't need anymore dt.
	- the queue of the paper is back :)

So, cleaning will be called when we are above a certain threshold. It can be
triggered at a regulat interval (dt2) or when inserting a new item make the
node exceed the threshold. Using the second solution, we also remove the
need of dt2.

The goal of the cleaning is to remove enough items to be xx% under the
threshold. During the cleaning, new incomming RFitems are ignored.

I have an additionnal remark concerning the RFs from the user. Like we see in
logs, some users, after having done a query, will click on every links (or a
lot of links). That will generate a lots of RFitems for that query and give it
a good popularity (rate_max will be high). So, for one query, you probably
need to limit the number of user feedbacks (at the browser feedback client
level).

THE PROBLEM
-----------

The problem is not cleaning. The problem is that a new popular item that
*should* be stored cannot be stored because of the time needed to become
popular is not sufficient (and is cleaned before).

Rate computation
----------------

Unit of time: day

rate = number of item last day / node_rate

rate will never be computed because it's a live value (we compute it when
we need it), but at each packet arrival we compute it and update if needed
max_rate (max_rate cannot be higher if computed between packet arrival
rather than just after an arrival).

queue:
	pro:
		- permits more complex computations
		- we can compute rate/max_rate when we wants
	cons:
		- queue size should be infinite

counter:
	pro:
		- only a counter to store and increment
	cons:
		- no advanced computations
		- we MUST compute/refresh rates at regular intervals
		- size of the interval is not easy to choose...

When we reach a limit and call cleaning, cleaning will clean X% under the
actual point. It's important that the time between this cleaning and the
next one is greater than between 2 rates computations.

1'000'000 RFItems/day, 100 nodes
=> 10'000 RFItems/day/node
if max size == 250'000 and cleaning of 10%
=> clean 25'000 items => should be able to run 2.5 days before
next cleaning

NEW IMPLEM
----------

- 1'000'000 operations/day
- 500'000 RFi and 500'000 queries
- 100 nodes
- max 250'000 (Q, D)/node => max 25'000'000 (Q, D)
- (Q, D) expiration: 5 days

- cleaning 1), every hour
- if max reached: cleaning all => -10%

=> 6 RFi and 6 queries /s
=> 144 speedup (1 day in 10 minutes) , => 860 /s

We consider most rates as number of items / day. RFitems rate and max_rate
are relative to overall rate. So, even if the RFitem speed/traffic evolve,
rates are still comparable. Delegation would add a new problem because this
rates will be less comparable because we should receice some additionnal
traffic.

-----
day = 600
qd_expiration = 1 * day

[COLFEED] N: cleaning summary    q    3599    d    2592    rfitems    8586
[COLFEED] Different queries:    190921
[COLFEED] Different docs:    163083
[COLFEED] Different RFitems (Q, D):    398404
[COLFEED] queries doc pointers    2.0867479219153    max    273    sexy swimwear
[COLFEED] doc queries pointers    2.4429523616809    max    3501    http://en.wikipedia.org
213106 ko


Place mémoire:
	#(Q, D) * (#(queries doc pointers) * #(avg bits rfitem) * 2 + #snippet + #extra)
	398404 * (2 * 10(?) * 2 + 200 + 40) = 90Mo
-----

Rates are measured by day !

--]]

alog = log.new(3, "[COLFEED]")

-- Representative time unit (base for all rates)
-- permits to speed up or slow down true days...
day = 600
bf_size = 8192

qd_expiration = day

-- Delegation
--max_delegation = 8 -- no more useful, undelegation are automatic
delegation_avg_factor = 1.8 -- 1.8
delegation_fraction_factor = 12 -- 10
delegation_contract_factor = 0.25
-- delegation_expiration = synchronization too in my implem
delegation_expiration = 10 * day -- day / 3 -- each 8 hours
delegation_eval_cycles = 4
delegation_min_peers = 1
-- queries for which we are a delegate
-- delegate_q[query] = {count, rate, time}
delegate_q = {}
--delegates = {} -- delegates[q] = {nodes with delegations}

-- RFitems
count_transits = 0
count_arrivals = 0
arrivals_time_queue = {}
arrivals_time_queue_size = 100
transits_time_queue = {}
transits_time_queue_size = 100

-- Will be computed from count_arrivals or arrivals_time_queue
rate_eval_cycles = 4
arrivals_rate = nil
transits_rate = nil

num_compute_rates = 24 * 6 -- each 10 minutes
num_compute_rfi_rates = 1 -- once each day
num_cleaning = 24
num_delegation_manager = 24 -- once per half hour
num_undelegation_manager = 24 -- once per half hour

-- query => {docs}
queries = {}

-- url => {title, qds = {qds}}
-- qds: query => {count, max_rate, rate, rate_count, rate_queue*, snippet, dp}
-- or (not used)
-- qds: query => {count, max_rate, time_queue*, snippet, dp}
docs = {}
qds_time_queue_size = 10
qds_rate_queue_size = 10

-- for efficient watching:
num_qds = 0

max_qds_size = 100000 -- ~ 50 Mo

-- store how many items we receive for each peer
-- {id, ip, port,
-- arrivals_count, arrivals_rate, transits_count, transits_rate}
-- this table will always be << number of pastry nodes and easy to
-- maintain
from_peer = {}

-- For delegation
watching_peers_queries = {}
watching_peers = false

-- for special test
query0_count = 0

function rates_manager()
	while events.sleep(day / num_compute_rates) do
		alog:notice("compute_rates")
		-- TODO more evolved formula based on arrivals_time_queue, transits_time_queue
		-- We do not compute them if we have not received enough samples.
		arrivals_rate =
				compute_rate("count_arrivals", count_arrivals, rate_eval_cycles) *
				num_compute_rates
		transits_rate =
				compute_rate("count_transits", count_transits, rate_eval_cycles) *
				num_compute_rates

		--alog:print("arrival: ", count_arrivals, arrivals_rate)
		--alog:print("transit: ", count_transits, transits_rate)

		for k, e in pairs(from_peer) do
			e.arrivals_rate =
					compute_rate('_peer_arrival_'..k, e.arrivals_count, rate_eval_cycles) *
					num_compute_rates
			e.transits_rate =
					compute_rate('_peer_transit_'..k, e.transits_count, rate_eval_cycles) *
					num_compute_rates
		end

		for k, e in pairs(delegate_q) do
			e.rate =
					compute_rate('_delegate_'..k, e.count, rate_eval_cycles) *
					num_compute_rates
		end
	end
end

function rfi_rates_manager()
	while events.sleep(day / num_compute_rfi_rates) do
		alog:notice("compute_rfi_rates")
		for _, doc in pairs(docs) do
			for _, qd in pairs(doc.qds) do
				qd.rate = qd.rate_count * num_compute_rfi_rates
				qd.rate_count = 0
				table.insert(qd.rate_queue, 1, qd.rate)
				if #qd.rate_queue > qds_rate_queue_size then
					table.remove(qd.rate_queue)
				end
				if qd.rate > qd.max_rate then
					qd.max_rate = qd.rate
				end
			end
		end
	end
end

function cleaning_one_manager()
	while events.sleep(day / num_cleaning) do
		cleaning_one()
	end
end

function cleaning_one()
	alog:notice("cleaning_one")
	local prev_queries, prev_docs, prev_qds = misc.size(queries), misc.size(docs), num_qds
	local limit = misc.time() - qd_expiration
	for url, doc in pairs(docs) do
		for query, qd in pairs(doc.qds) do
			if qd.last < limit then
				delete_qd(query, url)
			end
		end
	end

	alog:notice("cleaning one summary", "queries", prev_queries - misc.size(queries),
			"docs", prev_docs - misc.size(docs), "rfitems", prev_qds - num_qds)
print("cleaning one summary", "queries", prev_queries - misc.size(queries),
			"docs", prev_docs - misc.size(docs), "rfitems", prev_qds - num_qds)
	return prev_qds - num_qds
end
function cleaning_two() end
function cleaning_three() end
function cleaning_four() end

-- Analysis the rate of (the most active) incomming peers
function peer_stats()
	local peers, sum = {}, 0

	for _, p in pairs(from_peer) do
		sum = sum + p.arrivals_rate
	end
	local avg = sum / misc.size(from_peer)

	-- We consider only peers forwarding more than the average
	for _, p in pairs(from_peer) do
		if p.arrivals_rate > avg then
			table.insert(peers, p)
		end
	end
	table.sort(peers, function(a, b) return a.arrivals_rate < b.arrivals_rate end)

	-- We ask them for their (global) arrival rates
	local peers_sum, c = 0, 0
	for _, p in pairs(peers) do
		local ok, r = rpc.a_call(p, "arrivals_rate", g_timeout)
		if ok then
			p.arrivals_rate = r[1]
			peers_sum = peers_sum + r[1]
			c = c + 1
		end
	end
	if c < #peers then return nil, "peer contact error" end
	return peers, peers_sum / #peers, avg
end

--function num_delegates()
	--local c = 0
	--for _, q in pairs(delegates) do
		--c = c + #q
	--end
	--return c
--end

function ndiff(k1, k2)
	if k1 > k2 then return k1 - k2 else return k2 - k1 end
end

-- remotly called by "master" (or the one that delegates us)
function delegate(q, initial_rate, master)
	alog:notice("delegate "..q.." from "..master.ip..":"..master.port)
	delegate_q[q] = {count = 0, rate = 0,
			time = misc.time(), initial_rate = initial_rate}
end

function undelegate(q)
	alog:notice("undelegate "..q)
	-- Remove delegation
	delegate_q[q] = nil
	-- TODO find and sync the master
	-- I think we must have a delegation buffer for each query we are
	-- delegates, then we can pack it and send it to the master for
	-- synchronization. Master do synchronization and we get back the result.
end

-- TODO remove contract, identify the node that will receive this query
-- (normally this is the one that delegates us, but it can have disapeard),
-- ask it its rate and choose if the delegation is still worth.
function undelegation_manager()
	while events.sleep(day / num_undelegation_manager +
			math.random(day / num_undelegation_manager)) do
		local t = misc.time()
		for q, ns in pairs(delegate_q) do
			--if t > ns.time + rate_eval_cycles * (day / num_compute_rates) and
					--(t > ns.time + delegation_expiration * ns.rate / ns.initial_rate
					--or ns.rate < ns.initial_rate / 3) then
			if t > ns.time + rate_eval_cycles * (day / num_compute_rates) and
					ns.rate < ns.initial_rate * delegation_contract_factor and
					math.random(1) == 1 then
				undelegate(q)
			end
		end
	end
end

function delegation_manager()
	while events.sleep(day / num_delegation_manager +
			math.random(day / num_delegation_manager)) do
		alog:notice("delegation_manager")

		-- Sanity checks
		-- We do nothing if there is no more activity
		-- (maybe a temporary network problem)
		-- (either delegation AND undelegation)
		if misc.size(from_peer) > 0 and arrivals_rate and arrivals_rate > 100 then
--log:print("DELEGATION 1")

			-- Analysis the rate of incomming peers
			local peers, m = peer_stats()

--if peers then
--log:print("DELEGATION considering "..#peers.." of (global) arrival avg "..m)
--end

			-- We will try to delegate if we are over the average
			-- If peers < 2, average is meaningless.
			-- I'm not convinced about this test, but I keep it ATM as a security...
			if peers and #peers >= delegation_min_peers and
					arrivals_rate > m * delegation_avg_factor then
				--if num_delegates() < max_delegation then

--log:print("PREDELEGATION analysis", arrivals_rate)

				-- We need to analyse what query comming from who is worth delegation
				watching_peers = true
				events.sleep((day / num_compute_rates) * delegation_eval_cycles)
				watching_peers = false
				local wpq = watching_peers_queries
				watching_peers_queries = {}
				
--for pid, e in pairs(wpq) do
--for q, rate in pairs(e) do
	--print("", pid, q, rate)
--end
--end
				-- We recompute for more accuracy
				local peers, m = peer_stats()

				if peers and #peers >= delegation_min_peers and arrivals_rate > 100 and
						arrivals_rate > m * delegation_avg_factor then
--log:print("DELEGATION 3")

					-- best watching peers queries
					local bwpq = {}
					for pid, e in pairs(wpq) do

						-- consider only queries from 'peers'
						for _, p in pairs(peers) do
							if p.id == pid then

								-- keep the most important query
								local best_r, best_q = 0, nil
								for q, rate in pairs(e) do
									-- daily rate
									rate = rate * (num_compute_rates / delegation_eval_cycles)
									if rate > best_r then
										best_r = rate
										best_q = q
									end
								end
								bwpq[pid] = p
								bwpq[pid].q = best_q
								bwpq[pid].rate = best_r
								break
							end
						end
					end

log:print("DELEGATION summary")
					for _, p in pairs(bwpq) do
						log:print("QUERY "..p.q.." FROM "..p.ip..":"..p.port.."("..p.id..") "..
								"RATE "..p.rate)
					end

					-- Order the queries to minimize the distance to avg from all the node

					-- Compute distance from average
					local avg = ((m * #peers) + arrivals_rate) / (#peers + 1)
					local base_dist = 0
					for _, p in pairs(peers) do
						base_dist = base_dist + ndiff(avg, p.arrivals_rate)
					end

					local best_dist, best = math.huge, nil
					for _, p in pairs(bwpq) do

						-- distance to avg if we choose that peer as delegate
						dist = base_dist + ndiff(avg, arrivals_rate - p.rate)
								- ndiff(avg, p.arrivals_rate)
								+ ndiff(avg, p.arrivals_rate + p.rate)

--print("", "for query", p.q, "of peer", p.id, "=> dist", dist)
						if dist < best_dist then
							best_dist = dist
							best = p
						end
					end

print("", "WINNER", best.q, best.rate, "of peer", best.port, best.id, "=> dist", best_dist)
					if best.rate > arrivals_rate / delegation_fraction_factor and
							best.rate > 400 then -- TODO pas bien, en attendant mieux...
						-- TODO send delegation data
						local ok, r = rpc.a_call(best,
								{"delegate", best.q, best.rate, job.me}, g_timeout)
						if ok and delegate_q[best.q] then
							-- We already was a delegate for this query
							--undelegate(best.q)

							--local prev_rate = delegate_q[best.q].initial_rate
							--delegate_q[best.q].initial_rate =
									--prev_rate * ( 1 - (best.rate / delegate_q[best.q].rate))
						end
					end
				end
			end
		end
	end
end

function colfeed_stats()
	local s_queries, s_docs = misc.size(queries), misc.size(docs)
	alog:print("Different queries:", s_queries)
	alog:print("Different docs:", s_docs)
	local tot, tot_r, rate, max_rate = 0, 0, 0, 0
	for url, doc in pairs(docs) do
		for query, qd in pairs(doc.qds) do
			tot = tot + 1
			if qd.rate then
				tot_r = tot_r + 1
				rate = rate + qd.rate
				if qd.max_rate > max_rate then
					max_rate = qd.max_rate
				end
			end
		end
	end
	alog:print("Different RFitems (Q, D):", tot, "with rate:", tot_r,
			"avg rate:", rate / tot_r, "max rate:", max_rate)

	local tot, max = 0, 0
	local q = nil
	for query, docs in pairs(queries) do
		local s = misc.size(docs)
		tot = tot + s
		if s > max then
			max = s
			q = query
		end
	end
	alog:print("queries doc pointers", tot / s_queries, "max", max, q)

	local tot, max = 0, 0
	local u = nil
	for url, doc in pairs(docs) do
		local s = misc.size(doc.qds)
		tot = tot + s
		if s > max then
			max = s
			u = url
		end
	end
	alog:print("doc queries pointers", tot / s_docs, "max", max, u)
				
	for s, p in pairs(from_peer) do
		alog:print("FROM "..p.ip..":"..p.port.."("..p.id..") "..
				"ARRIVAL tot: "..p.arrivals_count.." rate: "..p.arrivals_rate.." "..
				"TRANSIT tot: "..p.transits_count.." rate: "..p.transits_rate)
	end
end

function delete_qd(query, url)
	--alog:debug("delete_qd", query, url)
	docs[url].qds[query] = nil
	if not next(docs[url].qds) then
		docs[url] = nil
	end
	queries[query][url] = nil
	if not next(queries[query]) then
		queries[query] = nil
	end
	num_qds = num_qds - 1
end

function store(rfi)
	local url = rfi.d.url
	local query = rfi.q

	if not docs[url] then
		docs[url] = { qds = {} }
	end
	-- we always refresh the title
	docs[url].title = rfi.d.title

	if not queries[query] then
		queries[query] = {}
	end
	queries[query][url] = true

	if not docs[url].qds[query] then

		docs[url].qds[query] = {
			snippet = rfi.d.snippet,
			dp = rfi.d.dp,
			count = 1,

			-- Used to compute the rate at regular intervals with dt
			rate_count = 1,
			rate = nil,
			rate_queue = {},

			-- Used to compute the rate at any time
			--time_queue = {},

			max_rate = 0,
			first = misc.time(),
			last = misc.time()
		}
		num_qds = num_qds + 1
	else

		docs[url].qds[query].count = docs[url].qds[query].count + 1
		docs[url].qds[query].snippet = rfi.d.snippet
		docs[url].qds[query].dp = dbits.pack(
				dbits.dor(
					dbits.unpack(docs[url].qds[query].dp, bf_size),
					dbits.unpack(rfi.d.dp, bf_size)))
		docs[url].qds[query].rate_count = docs[url].qds[query].rate_count + 1
		docs[url].qds[query].last = misc.time()
	end

	-- Update rate
	--local qd = docs[url].qds[query]
	--local now = misc.time()
	--table.insert(qd.time_queue, 1, now)
	--if #qd.time_queue > qds_time_queue_size then
		--table.remove(qd.time_queue)
	--end

	--local rate = rfi_rate(qd.time_queue)
	--if rate and rate > qd.max_rate then
		--qd.max_rate = rate
	--end
end

function reply(msg)
	local r = {}
	if queries[msg.q] then
		local t = misc.time()
		msg.up = dbits.unpack(msg.up, bf_size)
		local i = 0
		for url, _ in pairs(queries[msg.q]) do
			local o = {
				url = url, 
				title = docs[url].title,
				snippet = docs[url].qds[msg.q].snippet,
				n = sim_jaccard(msg.up, dbits.unpack(docs[url].qds[msg.q].dp, bf_size))
			}
			table.insert(r, o)
			i = i + 1
			-- We privilege overall reactivity over query speed
			if i % 2 == 0 then events.yield() end
		end
		table.sort(r, function(a, b) return a.n < b.n end)

		-- TODO reply the 10 bests
		return r, #r, misc.time() - t
	else
		return nil, 0, 0
	end
end

function inc_stats(peer, q, arrival)
	if arrival then
		count_arrivals = count_arrivals + 1

		-- delegation stats
		if delegate_q[q] then
			delegate_q[q].count = delegate_q[q].count + 1
		end

		if q == "query 0" then
			query0_count = query0_count + 1
		end
	else
		count_transits = count_transits + 1
	end

	if peer then

		if not from_peer[peer.id] then
			from_peer[peer.id] = {id = peer.id, ip = peer.ip, port = peer.port,
					arrivals_count = 0, arrivals_rate = 0,
					transits_count = 0, transits_rate = 0}
		end

		if arrival then
			from_peer[peer.id].arrivals_count =
					from_peer[peer.id].arrivals_count + 1

			-- request for more stats (for delegation)
			if watching_peers then
				if not watching_peers_queries[peer.id] then
					watching_peers_queries[peer.id] = {}
				end
				if not watching_peers_queries[peer.id][q] then
					watching_peers_queries[peer.id][q] = 0
				end
				watching_peers_queries[peer.id][q] =
						watching_peers_queries[peer.id][q] + 1
			end

		else
			from_peer[peer.id].transits_count =
					from_peer[peer.id].transits_count + 1
		end
	end
end

-- return msg, T, [reply]
-- Can modify msg, modify destination (T) or stop here (nil) with reply
function transit(msg, key, T)
	if msg.typ == "#colfeed_rfi#" then
		if delegate_q[msg.rfi.q] then
			--alog:debug("DELEGATE RFI", msg.rfi.q)
			thread(function() arrival(msg, key) end)
			return msg, nil, nil
		else
			--alog:debug("TRANSIT RFI", msg.rfi.q)
			inc_stats(msg.prev, msg.rfi.q, false)
			msg.prev = job.me
		end
	elseif msg.typ == "#colfeed_q#" then
		if delegate_q[msg.q] then
			--alog:debug("DELEGATE Q", msg.q)
			thread(function() arrival(msg, key) end)
			return msg, nil, nil
		else
			--alog:debug("TRANSIT Q", msg.q)
			inc_stats(msg.prev, msg.q, false)
		end
	end
	return msg, T
end

function arrival(msg, key)
		
	if msg.typ == "#colfeed_rfi#" then

		-- Optimization to reply ASAP
		thread(function()
			--alog:debug("ARRIVAL RFI", msg.rfi.q)
			inc_stats(msg.prev, msg.rfi.q, true)
			store(msg.rfi)
		end)

		--return {msg.rfi.q, count_arrivals, count_transits, msg.count_hops, msg.hops}
		return {msg.rfi.q, count_arrivals, msg.count_hops, msg.hops}
	elseif msg.typ == "#colfeed_q#" then

		-- Optimization to reply ASAP
		thread(function()
			--alog:debug("ARRIVAL Q", msg.q)
			inc_stats(msg.prev, msg.q, true)
		end)

		return reply(msg)
	end
end

---------
---------

function log_load()
	while events.sleep(5) do
		print(misc.time(), "LOAD", arrivals_rate, misc.size(delegate_q),
				job.me.ip, job.me.port, job.me.id)
	end
end

function log_super()
	while events.sleep(30) do
		local active = 0
		if delegate_q["query 0"] then
			active = 1
		end
		print(misc.time(), "SUPER", query0_count,
				active, job.me.ip, job.me.port, job.me.id)
		query0_count = 0
	end
end

function log_bench()
	local prev = 0
	while events.sleep(10) do
		print("BENCH", "rate", count_arrivals - prev, "tot", count_arrivals, "mem",  gcinfo())
		prev = count_arrivals
	end
end

-- TODO Compute the current rate of an RFItem (based on queue)
-- WILL NOT BE USED
--function rfi_rate(queue)
	--if not arrivals_rate then
		--return nil, "waiting for node arrival rate"
	--end

	-- We count number of RFitem received during this day
	--local limit, c = misc.time() - day, 0
	--for _, v in ipairs(queue) do
		--if v > limit then
			--c = c + 1
		--else
			--break
		--end
	--end

	--if c == qds_time_queue_size then
		-- the queue is full of recent items
		
		--if rfi.first < limit then
			-- we do the extrapolation for 1 day...
		
		--else
			--return nil
		--end
	--else
		--return c / arrivals_rate
	--end
--end

------------------------------------------------------------------


function static_id(total, position)
	local max = 2^bits
	local inc = max / total
	local cur = 0
	for i = 1, total do
		if position == i then
			local id = convert_base(cur, 10, base)
			while #id < key_s do id = "0"..id end
			return id
		end
		cur = cur + inc
	end
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

	-- COLFEED
	thread{rates_manager, rfi_rates_manager, delegation_manager, undelegation_manager,
			cleaning_one_manager, log_bench}
	events.periodic(30, colfeed_stats)
end)
