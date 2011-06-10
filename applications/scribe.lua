--[[
	Lua Pastry Protocol Implementation
	Copyright (C) 2007 Lorenzo Leonini - University of Neuchâtel
	http://www.leonini.net
	netslave [at] leonini (dot) net
--]]

--[[
NOTES:

We not only hash IP, but IP-port, like that we can even test the protocol
locally.

A node is a triplet {id (key), ip, port} like stored in A or in routing
and leaf tables.

b = 4 (=> base 16) will be assumed in our implementation because we will use hexadecimal
strings and string operation will depend of this reprensentation.

In our implementation, when we do routing, we always reply the target node
reached by the message. This addition will provide an easy way to find the
father (the next forwarding node) in Scribe.
--]]
--[[
BEGIN SPLAY RESSOURCES RESERVATION

nb_splayds 100
splayd_version 0.8
network_max_sockets 128
max_mem 20288000
disk_max_size 1048576000

END SPLAY RESSOURCES RESERVATION
--]]

--[[ Libraries ]]--
require"splay.base"
rpc = require"splay.rpc"
ev = events
evp = require"crypto.evp"
hmac = require"crypto.hmac"

log.set_level(1)

--[[ Print an array with l levels of depth (useful for debug) ]]--
function print_r(a, l, p)
	local l = l or 2 -- level
	local p = p or "" -- indentation (used recursivly)
	if type(a) == "table" then
		if l > 0 then
			for k, v in pairs(a) do
				io.write(p .. "[" .. tostring(k) .. "]\n")
				print_r(v, l -1, p .. "    ")
			end
		else
			print(p .. "*table skipped*")
		end
	else
		io.write(p .. tostring(a) .. "\n")
	end
end

pd_t = 10
tc, tr, ti, sub = misc.table_concat, table.remove, table.insert, string.sub

-- Implementation parameters
-- key length 2^bits (max 160 because using SHA and divisible by 4)
b, l, bits = 4, 16, 128 -- default 4, 16, 128

-- A: us, R: routing table, L[i,s]: inferior and superior leaf set
-- Li sorted from greater to lower, Ls sorted from lower to greater
A, R, Li, Ls = {}, {}, {}, {}

key_size = math.log(math.pow(2, bits))/ math.log(math.pow(2, b))

if key_size < math.pow(2, b) then
	print("Key size must be greater or equal than base")
	os.exit()
end
if b ~= 4 then
	print("b must be 4, because base 16 (hexadecimal) is needed in one function.")
	os.exit()
end

-- initialize empty lines of an empty routing table
for i = 0, key_size - 1 do R[i] = {} end

function compute_id(o) return sub(evp.new("sha1"):digest(o), 1, bits / 4) end
function num(key) return tonumber("0x"..key) end -- Hex dependant
function diff(key1, key2) return math.abs(num(key1) - num(key2)) end
function p(o, i) if i == 0 then return 0 else return num(sub(o, i, i)) end end
function between(i, a, b)
    if b >= a then return i > a and i < b else return i > a or i < b end
end

-- calculate our distance from a node
function ping(node)
	log.write("ping "..node.id)
	local t = misc.time()
	if rpc.ping(node) then return misc.time() - t else return math.huge end
end

-- return the length of the shared prefix
function shl(A, B)
	for i = 1, key_size do if p(A, i) ~= p(B, i) then return i - 1 end end
	return key_size
end
function row_col(key)
	local row = shl(key, A.id)
	return row, p(key, row + 1)
end

-- Entry point when we receive a new node.
function insert(node)
	log.write("insert "..node.id)
	if node.id == A.id then return end
	local t = ping(node)
	if t ~= math.huge then
		local r, l = insert_route(node, t), insert_leaf(node)
		if r or l then rpc.call(node, {'notify', A}) end
	else
		log.write("  received node is down")
	end
end

function insert_route(node, t)
	log.write("insert_route "..node.id)
	local row, col = row_col(node.id)
	local r = R[row][col]
	log.write("   at pos "..row..":"..col)
	-- if the slot is empty, or there is another node that is more distant
	-- => we put the new node in the routing table
	if not r or (r and r.id ~= node.id and t < ping(r)) then
		R[row][col] = node
		return true
	end
end

function insert_leaf(node)
	log.write("insert_leaf "..node.id)
	local a, b = insert_one_leaf(node, Li), insert_one_leaf(node, Ls, true)
	if a or b then
		while #Li > l / 2 do tr(Li) end
		while #Ls > l / 2 do tr(Ls) end
	end
	return a or b
end

function insert_one_leaf(node, leaf, sup)
	for i = 1, l / 2 do
		if leaf[i] then
			if node.id == leaf[i].id then break end
			if (not sup and between(num(node.id), num(leaf[i].id), num(A.id))) or
				(sup and between(num(node.id), num(A.id), num(leaf[i].id))) then
				ti(leaf, i, node)
				return true
			end
		else
			leaf[i] = node
			return true
		end
	end
	return false
end

-- leaf inf and sup mixed with each elements only once
function leafs()
	local fl = Li
	for _, e in pairs(Ls) do
		local found = false
		for _, e2 in pairs(Li) do
			if e.id == e2.id then
				found = true
				break
			end
		end
		if not found then
			fl[#fl + 1] = e
		end
	end
	return fl
end

function reset_leaf(node)
	for i, n in pairs(Li) do if node.id == n.id then tr(Li, i) end end
	for i, n in pairs(Ls) do if node.id == n.id then tr(Ls, i) end end
end

function range_leaf(D) -- including ourself in the range
	local min, max = num(A.id), num(A.id) -- Way to put ourself in the range.
	if #Li > 0 and #Ls > 0 then min = num(Li[#Li].id) max = num(Ls[#Ls].id) end
	if #Li > 0 and #Ls == 0 then min = num(Li[#Li].id) max = num(Li[1].id) end
	if #Li == 0 and #Ls > 0 then min = num(Ls[1].id) max = num(Ls[#Ls].id) end
	return num(D) >= min and num(D) <= max
end

function nearest_leaf(D) -- including ourself
	log.write("nearest_leaf "..D)
	local d, j, L = math.huge, nil, tc(leafs(), {A})
  for i, n in pairs(L) do
		if diff(D, n.id) < d then
			d = diff(D, n.id)
			j = i
		end
	end
	return L[j]
end

function repair(row, col, id)
	log.write("repair "..row.." "..col, 2)
	local r = row
	while r <= key_size - 1 and not rfr(r, row, col, id) do r = r + 1 end
end

-- Use row 'r' to contact a node that could give us a replacement for the node
-- at pos (row; col)
-- id: to avoid re-inserting the same failed node
function rfr(r, row, col, id) -- repair from row
	log.write("rfr "..r.." "..row.." "..col.." "..id, 2)
	for c, node in pairs(R[r]) do
		if c ~= col then
			local r = rpc.call(node, {'node', row, col})
			-- We verify that to no accept the same broken node than before.
			if r and r.id ~= id then
				insert(r)
				log.write("  repaired with "..r.id, 2)
				return true
			end
		end
	end
end

function failed(node)
	log.write("failed "..node.id, 2)
	local row, col = row_col(node.id)
	reset_leaf(node)
	if R[row][col] and R[row][col].id == node.id then
		R[row][col] = nil
		ev.thread(function() repair(row, col, node.id) end) 
	end
end

-- local, we want to join "node"
function join(node)
	log.write("join "..node.id)
	local r, err = rpc.call(node, {'route', {typ = "#join#"}, A.id})
	if not r then return nil, err end
	for _, e in pairs(r) do
		if e.id then
			insert(e)
		else
			for _, n in pairs(e) do
				insert(n)
			end
		end
	end
	return true
end

function try_route(msg, key, T, no_forward)
	local reply = nil -- modified reply from the forward function()
	if not no_forward then
		msg, T, reply = forward(msg, key, T)
	end
	if not T then return reply end -- application choose to stop msg propagation
	local n = rpc.call(T, {'route', msg, key})
	if n then
		if msg.typ == "#join#" then
			local row, col = row_col(key)
			ti(n, R[row])
		end
		return n
	else 
		failed(T)
		return route(msg, key, no_forward)
	end
end

function route(msg, key, no_forward) -- Pastry API (+ no_forward parameter)
	log.write("route "..key.." "..tostring(msg.typ))
	if key ~= A.id then
		local n, T = nil, nil -- replied node, target node
		local row, col = row_col(key)
		if range_leaf(key) then -- key is within range of our leaf set
			T = nearest_leaf(key) -- find the L[i] where |key - L[i]| is minimal
			if T.id ~= A.id then return try_route(msg, key, T, no_forward) end -- if not ourself
		else -- use the routing table
			T = R[row][col]
			if T then
				return try_route(msg, key, T, no_forward)
			else
				-- rare case
				-- If we found a node that match criterias, we take it. We don't
				-- search for the best one.
				for _, T in pairs(leafs()) do
					if shl(T.id, key) >= row and diff(T.id, key) < diff(A.id, key) then
						return try_route(msg, key, T, no_forward)
					end
				end
				-- since we begin at the row l, all the nodes will have a prefix >= l
				for r = row, key_size - 1 do 
					for c, T in pairs(R[r]) do
						if T and diff(T.id, key) < diff(A.id, key) then
							return try_route(msg, key, T, no_forward)
						end
					end
				end
			end
		end
	end
	-- we are the best node for that key
	deliver(msg, key)
	if msg.typ == "#join#" then return {A, leafs()} else return {A} end
end

-- check the leaf set, to see if everybody still there
function keep_alive()
	log.write("keep_alive")
	local L = leafs()
	for _, ln in pairs(L) do
		if ping(ln) == math.huge then
			failed(ln)
		end
	end
	-- If we miss some leaf, ask our other leaf to fill it
	-- We always ask to avoid the fact to be adjacent nodes that will never know
	-- them.
	local r = rpc.call(misc.random_peek_one(L), {'leafs'})
	if r then for _, n in pairs(r) do insert(n) end end
end

-- RPC aliases
function node(row, col) return R[row][col] end
function notify(node) insert(node) end

-- Pastry API
function send(msg, node) return rpc.call(node, {'route', msg, node.id}) end

-------------------------------- SCRIBE ------------
--[[
Problem pour tester splitstream en dehors d'un simulateur car en fait chaque
node connait normallement sa bande passante entrante et sortante. Le noeud
choisit donc k stripes de données correspondant à sa bande passante en entrée
et le nombre total d'enfants correspondant à sa bande passante en sortie.
--]]

-- If a node receive a join but it is not connected to the true root, it will
-- maybe deliver the message to himself but the array groups[groupkey] will not
-- be create because it is created on CREATE or when a node is a forward node,
-- not a deliver one.
--
-- Even if children are superior to max_children, we will accept at least one children
-- for each splitstream stripe.
max_children = 32

groups = {} -- groups we are in
backup_groups = {} -- groups we are in

function message_handler(msg)
	if type(msg.data) == "table" then
		print("", ">>>", tostring(msg.data[1]))
		messages[msg.data[1]] = true
		--log.write("DATA "..msg.data[1]..": "..msg.groupkey, 5)
	else
		print("", ">>>", tostring(msg.data))
	end
end

function count_children()
	local c = 0
	for _, group in pairs(groups) do
		for _, child in pairs(group.children) do
			if child.id ~= A.id then c = c + 1 end
		end
	end
	return c
end

-- check if a child is already part of a group
function is_child(groupkey, node)
	log.write("is_child() "..node.id.." of "..groupkey)
	for _, child in pairs(groups[groupkey].children) do
		if child.id == node.id then
			return true
		end
	end
	return false
end

function insert_child(groupkey, node)
	log.write("insert_child() "..node.id.." into group "..groupkey, 2)
	if not is_child(groupkey, node) then
		ti(groups[groupkey].children, node)
	end
end

function reject_child() -- splitsream conditions
	log.write("reject_child()", 2)
	if count_children() > max_children then

		-- we peek a children in the most populated group
		local gs = {}
		for groupkey, group in pairs(groups) do
			gs[#gs + 1] = {}
			gs[#gs].groupkey = groupkey
			gs[#gs].children = group.children
		end
		table.sort(gs, function(g1, g2)
				local c, d = 0, 0
				for _, child in pairs(g1.children) do
					if child.id ~= A.id then c = c + 1 end
				end
				for _, child in pairs(g2.children) do
					if child.id ~= A.id then d = d + 1 end
				end
				return c > d
			end)
		if #gs[1].children > 1 then
			local g = gs[1]
			local c, pos, max = 0, nil, 0
			for i, child in pairs(g.children) do
				if child.id ~= A.id then
					c = c + 1
					-- We reject the child with the bigger difference with us,
					-- this will avoid loops later.
					if max < diff(A.id, child.id) then
						max = diff(A.id, child.id)
						pos = i
					end
				end
			end
			if c >= 2 then -- we can't reject a soon if we have only one
				local n = g.children[pos]
				tr(groups[g.groupkey].children, pos) -- remove the rejected

				local msg = {}
				msg.typ = "REJECT"
				msg.groupkey = g.groupkey
				msg.source = A
				msg.data = {}

				for i, child in pairs(groups[g.groupkey].children) do
					if child.id ~= A.id then -- remove us from the list
						msg.data[#msg.data + 1] = child
					end
				end

				log.write("Rejected child: "..n.id, 2)
				send(msg, n)
			end
		end
	end
end

-- When we are the deliver node to receive some messages
-- We call this function only when we are the deliver node (root).
-- groups[groups] must node exists.
function create(groupkey)
	log.write("create() "..groupkey, 2)
	groups[groupkey] = {}
	groups[groupkey].children = {}
end

-- root node function (no, if a rejected child directly connect us to be his
-- parent) 
function scribe_join(msg)
	log.write("scribe_join() "..msg.groupkey, 2)
	if msg.groupkey == A.id then
		if not groups[msg.groupkey] then create(msg.groupkey) end
		if groups[msg.groupkey].parent then
			groups[msg.groupkey].parent = nil
		end
	end
	insert_child(msg.groupkey, msg.source)
end

-- target a node not necessary the root
function multicast(msg)
	log.write("multicast() "..msg.groupkey, 2)
	if groups[msg.groupkey] then
		for i, node in pairs(misc.dup(groups[msg.groupkey].children)) do
			if node.id == A.id then -- I'm a leaf of that group
				message_handler(msg)
			else
				ev.thread(function() 
					local r = send(msg, node)
					if not r then
						-- we remove this child
						table.remove(groups[msg.groupkey].children, i)
						--log.write("ERROR MULTICASTING", 5)
					end
				end)
			end
		end
	else
		log.write("Multicast for a group that we are not in: "..msg.groupkey, 4)
	end
end

-- target a node not necessary the root
function leave(msg) -- target a node not necessary the root
	log.write("leave() "..msg.groupkey, 2)
	if groups[msg.groupkey] then
		-- msg.source leave (it can be myself, if msg.source is me) or one of
		-- my children.
		for i, node in pairs(groups[msg.groupkey].children) do
			if node.id == msg.source.id then
				tr(groups[msg.groupkey].children, i)
				break
			end
		end

		-- There is no more children listening (and not myself because I would
		-- be in the children list), so I can said that I leave to my father so
		-- I will not still be a forward node.
		if #groups[msg.groupkey].children == 0 and groups[msg.groupkey].parent then
			msg.source = A -- myself this time
			send(msg, groups[msg.groupkey].parent)
			groups[msg.groupkey] = nil
		end
	else
		log.write("Cannot leave a group that we are not in: "..msg.groupkey, 4)
	end
end

-- i am rejected (target a (non root) node)
function reject(msg)
	log.write("reject() "..msg.groupkey, 2)
	if groups[msg.groupkey] then

		-- very important to destroy the parent because if the parent in the
		-- list is a dead node, we will still have no parent but it will be
		-- restored in the next keep_alive_scribe_parent
		groups[msg.groupkey].parent = nil

		local new_parent, min_time = nil, math.huge
		-- search for a new parent
		for _, p in pairs(msg.data) do
			local t = ping(p)
			if t < min_time then
				min_time = t
				new_parent = p
			end
		end
		if new_parent then
			log.write("New parent is "..new_parent.id, 2)
			msg.typ = "JOIN"
			msg.source = A
			local p = send(msg, new_parent)[1]
			groups[msg.groupkey].parent = p
		else
			log.write("No new parent :-(", 2)
		end
	else
		log.write("Receive a reject for a group we don't have ??? "..msg.groupkey, 4)
	end
end

function forward(msg, key, T) -- pastry API call
	log.write("forward() "..msg.typ.." "..key.." "..T.id, 2)
	if msg.typ == "JOIN" then
		if not groups[msg.groupkey] then
			groups[msg.groupkey] = {}
			groups[msg.groupkey].children = {}
		end

		-- TODO test and memorize here is we are a LEAF (do at last 1/2)

		insert_child(msg.groupkey, msg.source)

		msg.source = A
		groups[msg.groupkey].parent = route(msg, msg.groupkey, true)[1]
		if groups[msg.groupkey].parent.id == A.id then
			-- rare case when the old root is down and we are the nes
			groups[msg.groupkey].parent = nil
			
			-- TODO if we was not a leaf remove us as child (do at last 2/2) 
		end
		
		-- stop routing the original message,
		-- but reply this node (parent of the previous forwarding node)
		return msg, nil, {A}
	end
	return msg, T
end

function deliver(msg, key)
	log.write("deliver() "..msg.typ.." "..key, 2)
	if msg.typ == "CREATE" then
		create(msg.groupkey)
	elseif msg.typ == "JOIN" then
		if groups[msg.groupkey] then
			scribe_join(msg)
		else
			log.write("Error, we received JOIN without CREATE or not connected to the network", 5)
			log.write("Me: "..A.id.." group: "..msg.groupkey, 5)
			local str = "Leaf inf "
			for i = #Li, 1, -1 do str = str..Li[i].id.." " end
			log.write(str, 5)
			str = "Leaf sup "
			for i = 1, #Ls do str = str..Ls[i].id.." " end
			log.write(str, 5)
			for i = 0, 4 do
				local str = ""..i..": "
				for c = 0, math.pow(2, b) - 1 do
					if R[i][c] then
						str = str.." "..R[i][c].id
					else
						str = str.." -"
					end
				end
				log.write(str, 5)
			end
		end
	elseif msg.typ == "MULTICAST" then
		multicast(msg)
	elseif msg.typ == "LEAVE" then
		leave(msg)
	elseif msg.typ == "REJECT" then
		reject(msg)
	end
end

function keep_alive_scribe_parent()
	log.write("keep_alive_scribe_parent() ", 2)
	for groupkey, group in pairs(groups) do
		if groupkey ~= A.id then -- if we are no the root
			--if not group.parent or
			--		(group.parent and ping(group.parent) == math.huge) then

				-- parent loose, we search a new one
				local msg = {}
				msg.typ = "JOIN"
				msg.groupkey = groupkey
				msg.source = A
				local p = route(msg, groupkey, true)[1]
				if not p or p.id == A.id then
					-- We are not the original root but the best choice at the
					-- moment, anyway, we'll try again to recontact the original
					-- root later.
					groups[groupkey].parent = nil
				else
					groups[groupkey].parent = p
				end
			--end
		end
	end
end

function keep_alive_scribe_children()
	log.write("keep_alive_scribe_children() ", 2)
	for groupkey, group in pairs(groups) do
		for i = #group.children, 1, -1 do
			if ping(group.children[i]) == math.huge then
				table.remove(groups[groupkey].children, i)
			end
		end
	end
end

function debug_scribe()
	print("--------------------- scribe ------------------")
	print()
	for groupkey, group in pairs(groups) do
		print("Group: ", groupkey)
		if groupkey == A.id then
			print("", "I'm the root node.")
		else
			if not group.parent then
				print("", "Root node is missing !!")
			end
		end
		if group.parent then
			print("", "Parent: ", group.parent.id)
		end
		for _, child in pairs(group.children) do
			if child.id ~= A.id then
				print("", "Child: ", child.id)
			else
				print("", "Child: ", "myself")
			end
		end
	end
	print("----------------------------------------------")
end

--------------------------------------------

function print_route()
	local lines = 4
	if lines > key_size - 1 then lines = key_size - 1 end
	--for i = 0, key_size - 1 do
	for i = 0, lines do
		local str = ""..i..": "
		for c = 0, math.pow(2, b) - 1 do
			if R[i][c] then
				str = str.." "..R[i][c].id
			else
				str = str.." -"
			end
		end
		print(str)
	end
end

function print_leaf()
	local str = "Leaf inf "
	for i = #Li, 1, -1 do str = str..Li[i].id.." " end
	print(str)
	str = "Leaf sup "
	for i = 1, #Ls do str = str..Ls[i].id.." " end
	print(str)
end

function debug()
	print("_________________________________________")
	collectgarbage()
	print(gcinfo().." ko")
	print("ME:", A.id)
	print_route()
	print_leaf()
	print("_________________________________________")
	--print()
end

function speed_test()
	local r, err, try, t = nil, nil, 0
	local http = require"socket.http"
	local url = "http://mirror.switch.ch/ftp/software/mirror/debian/pool/main/l/lilo/lilo_22.6.1-9.3_amd64.deb"
	while r == nil and try < 3 do
		try = try + 1
		t = misc.time()
		r, err = http.request(url) -- blocking
	end
	if r then
		return string.len(r) / (misc.time() - t)
	else
		return nil, err
	end
end

function run()
	local s, err = speed_test() / 1024
	if not s or s < 100 then
		if not s then
			log.write("Speed test failed: "..err, 4)
		else
			log.write("Speed test failed (too slow "..s..")", 4)
		end
		return
	else
		-- We consider 1.5 less bandwith in upload (even if on planetlab it
		-- should be symmetric, we need 32ko for each children.
		max_children = math.floor(s / (16 * 1.5))
		log.write("START "..A.id.." with max children: "..tostring(max_children), 5)
-- TODO REEEEEEEEEEEEEEEEMMMMMMMMMOOOOOOOOOOVVVVVVVVVVEEEEEEEEEE
--max_children = 1
	end
	if not rpc.server(A.port) then
		log.write("Bind error.", 4)
		return
	end
	if arg[1] then
		local node = {}
		node.ip = A.ip
		node.port = A.port - 1
		node.id = compute_id(node.ip..node.port)
		join(node)
	end
	ev.periodic(debug, pd_t)
	ev.periodic(debug_scribe, pd_t)
	ev.periodic(keep_alive, pd_t)
	ev.periodic(keep_alive_scribe, pd_t)
	ev.periodic(backup, pd_t)
end

A.ip = "127.0.0.1"
A.port = 20000
if arg[1] then
	local d = tonumber(arg[1])
	A.port = A.port + d
end
A.id = compute_id(A.ip..A.port)
print("ME: "..A.id)

ev.thread(run)
ev.loop()
