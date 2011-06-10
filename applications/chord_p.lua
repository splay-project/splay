--socket = require"socket.core"
--rs = require"splay.restricted_socket"
--socket = rs.wrap(socket)
-----------------------------

require"splay.base"
rpc = require"splay.rpcq"

between, thread = misc.between_c, events.thread
n, predecessors, finger, successors, m, r = {}, {}, {}, {}, 32, 16

verify_timeout, rpc_timeout, ping_timeout = 60, 30, 30
check_predecessors_timeout, check_successors_timeout = 15, 15
stabilize_timeout, fix_fingers_timeout = 30, 10

acall_count, ping_count, find_successor_count = 0, 0, 0
max_rpc_client, max_rpc_server = 10, 15

-------------------------------
-- test pour rpcq (les limites doivent etre assez haute pour lui)
verify_timeout, rpc_timeout, ping_timeout = 120, 60, 30
max_rpc_client, max_rpc_server = 40, nil
r = 4
rpc.settings.clean_timeout = 30
rpc.settings.reconnect_interval = 10
 --lua ring.lua 192.42.43.30 192.42.43.30 20000
--rand_mess_17440520
--75: next error from 12.46.129.16:27662 1858867449 to 138.96.250.150:31000 1871259863
--75: next error from 12.46.129.16:27662 1858867449 to 192.42.43.30:20021 1875308007
--352: delivered in 162.70506286621
-------------------------------

log.global_level = 2
rpc.settings.max = max_rpc_client

-- TODO we could intelligently merge the successors list and our successors list
-- and avoid using check_successors().
-- TODO route using successors and predecessors
-- TODO rpc.max can replace all the locks to RPCs
--
-- NOTE we don't use successors list for routing
-- NOTE finger[1] (successor) is NEVER nil, in the worst case = ourself

_check_c = {}
_check_r = {}
function check(p)
	local s = p.ip..":"..p.port
	if not _check_c[s] or _check_c[s] < misc.time() - verify_timeout then
		log:debug("check", s)
		_check_r[s] = rpc.ping(p, ping_timeout)
		ping_count = ping_count + 1
		_check_c[s] = misc.time()
	end
	return _check_r[s]
end
function set_ok(p)
	local s = p.ip..":"..p.port
	_check_r[s] = true
	_check_c[s] = misc.time()
end
function set_failed(p)
	local s = p.ip..":"..p.port
	_check_r[s] = false
	_check_c[s] = misc.time()
end
function is_failed(p)
	local s = p.ip..":"..p.port
	if _check_c[s] and _check_c[s] > misc.time() - verify_timeout and
		not _check_r[s] then
		return true
	end
end

function insert_finger(s, fake)
	local ins = false
	if not finger[1] or finger[1].id == n.id then
		if not fake then
			finger[1] = s
		end
		ins = true
	end
	for i = 1, m do
		local v = (n.id + 2^(i - 1)) % 2^m
		if finger[i] then
			if between(s.id, v, finger[i].id) then
				if not fake then
					finger[i] = s
				end
				ins = true
			end
		else
			if between(s.id, v, n.id) then
				if not fake then
					finger[i] = s
				end
				ins = true
			end
		end
	end
	return ins
end

function repack_successors()
	-- remove empty slots
	local s = {}
	for _, v in pairs(successors) do
		table.insert(s, v)
	end
	successors = s
	table.sort(successors, function(a, b) return between(a.id, n.id, b.id) end)
	while #successors > r do table.remove(successors) end
end

function repack_predecessors()
	-- remove empty slots
	local s = {}
	for _, v in pairs(predecessors) do
		table.insert(s, v)
	end
	predecessors = s
	table.sort(predecessors, function(a, b) return between(a.id, b.id, n.id) end)
	while #predecessors > r do table.remove(predecessors) end
end

function insert_successors(s, fake)
	for _, e in pairs(successors) do
		if e.id == s.id then return end
	end
	if #successors < r or between(s.id, n.id, successors[#successors].id) then
		if not fake then
			table.insert(successors, s)
			repack_successors()
		end
		return true
	end
end

function insert_predecessors(s, fake)
	for _, e in pairs(predecessors) do
		if e.id == s.id then return end
	end
	if #predecessors < r or between(s.id, predecessors[#predecessors].id, n.id) then
		if not fake then
			table.insert(predecessors, s)
			repack_predecessors()
		end
		return true
	end
end

function insert_one(s)
	log:debug("insert_one", s.id)
	if s.id == n.id then return end

	if not is_failed(s) then
		if insert_finger(s, true) or
			insert_successors(s, true) or insert_predecessors(s, true) then
			log:debug("can be inserted", s.id)
			if check(s) then
				insert_finger(s)
				insert_successors(s)
				insert_predecessors(s)
			end
		end
	end
end

function insert(s)
	if s then -- can be nil if find_successor fail (max recursivity)
		if not s.id then
			for _, e in pairs(s) do
				thread(function()
					insert_one(e)
				end)
			end
		else
			thread(function()
				insert_one(s)
			end)
		end
	end
end

function failed(p)
	log:warning("failed", p.id, p.ip..":"..p.port)
	set_failed(p)
	local f = false
	for i, e in pairs(finger) do
		if e.id == p.id then
			finger[i] = nil
			f = true
		end
	end
	for i, e in pairs(successors) do
		if e.id == p.id then
			successors[i] = nil
			-- Try to insert the successor of the failing node in the finger table
			if f and successors[i + 1] then
				insert_finger(successors[i + 1])
			end
		end
	end
	repack_successors()
	for i, e in pairs(predecessors) do
		if e.id == p.id then predecessors[i] = nil end
	end
	repack_predecessors()
end

function acall(h, c, t)
	log:debug("acall", h.id)
	t = t or rpc_timeout
	acall_count = acall_count + 1
	local ok, reply
	if not is_failed(h) then
		ok, reply = rpc.acall(h, c, t)
		if h.id then -- no id = rdv node
			if ok then
				set_ok(h)
			else
				failed(h)
			end
		end
	else
		--print(misc.time(), "ISFAILED", h.id)
		ok, reply = false, nil
	end
	return ok, reply
end

function insert_missing(a, node)
	for _, n in pairs(a) do
		if n.id == node.id then
			return
		end
	end
	table.insert(a, node)
end

function all_nodes()
	local a = {}
	table.insert(a, n)
	for i = 2, m do
		if finger[i] then insert_missing(a, finger[i]) end
	end
	for _, p in pairs(successors) do
		insert_missing(a, p)
	end
	for _, p in pairs(predecessors) do
		insert_missing(a, p)
	end
	return a
end

function do_notify(node)
	log:debug("do_notify", node.id)
	local ok, reply = acall(node, {'notify', n, all_nodes()})
	if ok then
		insert(reply[1])
	end
end

-------------

function join(n0) -- n0: some node in the ring
	set_ok(n0)
	local ok, reply = acall(n0, {'find_successor', {id = n.id, typ = "join"}})
	if ok then
		insert(reply[2], true)
		do_notify(n0)
		return true
	end
end

function closest_preceding_node(id)
	log:debug("closest_preceding_node")
	for i = m, 1, -1 do
		if finger[i] and between(finger[i].id, n.id, id) then 
			return finger[i]
		end
	end
	return n
end

-- 'o' is an object (or a node) with (at least) o.id defined.
function find_successor(o)
	log:debug("find_successor")
	find_successor_count = find_successor_count + 1

	-- security
	if not o.count_sec then
		o.count_sec = 0
	else
		o.count_sec = o.count_sec + 1
	end
	if o.count_sec == 10 then
		if not o.hops then o.hops = {} end
		o.debug = true
	end
	if o.count_sec > 25 then
		log:error("recursivity max reached", n.id, o.id)
		for _, h in pairs(o.hops) do
			log:error("", h.id, h.ip..":"..h.port)
		end
		return nil
	end

	if not o.count_hops then
		o.count_hops = 0
	else
		o.count_hops = o.count_hops + 1
	end
	if o.hops then
		table.insert(o.hops, n)
	end

	--if between(id, n.id, (finger[1].id + 1) % 2^m) then
	-- en fait, quand on ne connait personne d'autre que nous, la condition sera
	-- fausse. on va ensuite forcement se renvoyer dans closest_preceding_node et
	-- ensuite rapeller find_successor sur nous (boucle sans fin)
	-- donc ici on va supposer que si finger 1 est nous, on ne connait personne
	-- d'autre et nous renvoyer directement.
	-- ceci se passe essentiellement quand on appelle fix_fingers, ensuite quand
	-- on est notifie, on remplace finger 1 par qqc de mieux...
	if finger[1].id == n.id or between(o.id, n.id, (finger[1].id + 1) % 2^m) then

		-- just to have it in the list...
		if o.hops then
			table.insert(o.hops, finger[1])
		end
		if o.origin then
			thread(function()
				if not acall(o.origin, {'reply', o, n}) then
					log:warning("callback failed", o.origin.ip, o.origin.port)
				end
			end)
		end

		if o.typ == "join" then
			return finger[1], all_nodes()
		else
			return finger[1], o
		end

	else
		local n0 = closest_preceding_node(o.id)
		local ok, reply = acall(n0, {'find_successor', o})
		if ok then
			return unpack(reply)
		else

			o.count_hops = o.count_hops - 1
			if o.hops then
				table.remove(o.hops)
			end

			return find_successor(o)
		end
	end
end

function stabilize()
	log:debug("stabilize")
	do_notify(finger[1])
end

function notify(n0, an)
	log:debug("notify")
	set_ok(n0)
	insert(n0)
	insert(an)
	return all_nodes()
end

function fix_fingers()
	refresh = (refresh and (refresh % m) + 1) or 1 -- 1 <= next <= m
	log:debug("fix_fingers", refresh)
	insert(find_successor({id = (n.id + 2^(refresh - 1)) % 2^m}))
end

function check_successors()
	log:debug("check_predecessors")
	if #successors > 0 then
		do_notify(misc.random_pick(predecessors))
	end
end

function check_predecessors()
	log:debug("check_successors")
	if #predecessors > 0 then
		do_notify(misc.random_pick(predecessors))
	end
end

-------------------------- INSTRUMENTATION FUNCTIONS -----------------------

-- DEPRECATED PART

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
	log.print("END OF TEST")
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
			log.print("QUERY "..q.hops.." "..q.deliver.." "..q.start_time)
		else
			log.print("FAILED "..q.start_time)
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
	log.print("KILL in 10s ")
	events.sleep(10)
	os.exit()
end

-- REFRESHED PART ---------------

r_d = {}
function ring(me)
	-- Now the function can return...
	thread(function()
		if r_d[me.msg] then
			log:print("RING: "..me.msg.." already")
			acall(me.origin, {'delivered', me}, 60)
		else
			r_d[me.msg] = me.msg
			log:print("RING: "..me.msg)
			-- UDP message will become too big !
			--table.insert(me.hops, n)
			me.count = me.count + 1

			if me.tick then
				thread(function()
					acall(me.origin, {'tick', me, n})
				end)
			end

			while not acall(finger[1], {'ring', me}) do
				acall(me.origin, {'next_error', me, n, finger[1]}, 60)
				events.sleep(1)
			end
		end
	end)
end

m_d = {}
function multicast(me)
	-- Now the function can return...
	thread(function()
		if not m_d[me.msg] then
			m_d[me.msg] = me.msg
			log:print("MULTICAST: "..me.msg)
			-- call for ourself !!!
			if me.call then
				log:print("calling "..me.call[1])
				thread(function() acall(n, me.call) end)
			end
			-- to get all the nodes in an easy way...
			if me.all then
				thread(function() acall(me.origin, {'delivered', me, n}) end)
			end
			if #successors > 0 then
				thread(function() acall(successors[1], {'multicast', me}) end)
			end
			local p_f = nil
			for i = m, 1, -1 do
				if finger[i] and finger[i].id ~= p_f then
					-- No threads, to keep a low load
					acall(finger[i], {'multicast', me})
					p_f = finger[i].id
				end
			end
		end
	end)
end

function debug()
	log:print()
	log:print("_________________________________________")
	collectgarbage()
	log:print("Mem: "..gcinfo().." ko", "acall", acall_count, "ping", ping_count, "find succ", find_successor_count)
	if socket.infos then
		log:print(socket.infos())
	end
	if rpc.infos then
		log:print(rpc.infos())
	end
	if events.infos then
		log:print(events.infos())
	end

	log:print("ME: "..n.id)
	local f_s = ""
	local p_f = nil
	for i = 1, m do
		if finger[i] then
			if finger[i].id ~= p_f then
				f_s = f_s..i..":"..finger[i].id.." "
			end
			p_f = finger[i].id
		end
	end
	log:print("finger", f_s)
	local s_s = ""
	for _, p in pairs(successors) do
		s_s = s_s..p.id.." "
	end
	log:print("successors", s_s)
	local s_s = ""
	for _, p in pairs(predecessors) do
		s_s = s_s..p.id.." "
	end
	log:print("predecessors", s_s)
	log:print("-----------------------------------------")
end

function debug_pl()
	log:print("____________________")
	log:print("ME: "..n.id)
if socket.infos then
	log:print(socket.infos())
end
if rpc.infos then
	log:print(rpc.infos())
end
	local f_s = ""
	local p_f = nil
	for i = 1, m do
		if finger[i] then
			if finger[i].id ~= p_f then
				f_s = f_s..i..":"..finger[i].id.." "
			end
			p_f = finger[i].id
		end
	end
	log:print("finger", f_s)
	local s_s = ""
	for _, p in pairs(successors) do
		s_s = s_s..p.id.." "
	end
	log:print("successors", s_s)
	local s_s = ""
	for _, p in pairs(predecessors) do
		s_s = s_s..p.id.." "
	end
	log:print("predecessors", s_s)
	log:print("--------------------")
end

function ressources_pl()
	log:print("______")
	collectgarbage()
	log:print("Mem: "..gcinfo().." ko", "acall", acall_count, "ping", ping_count, "find succ", find_successor_count)
	if socket.infos then
		socket.infos()
	end
	if events.stats then
		log:print(events.stats())
	end
	log:print("------")
end

watch_high = 0
watch_succ = false
max_no_succ = 0
function watchdog()
	if socket.stats then
		local ts, tr, ttcp, tudp = socket.stats()
		if ttcp > 25 then
			watch_high = watch_high + 1
		end
		if ttcp < 16 then
			watch_high = watch_high - 1
		end
		if watch_high < 0 then watch_high = 0 end
		if watch_high > 5 then
			--log:print("SUICIDE: too much sockets")
			--events.sleep(1)
			--os.exit()
		end
	end
	if #successors == r then
		watch_succ = true
	end
	if #successors < 3 and watch_succ then
		log:print("SUICIDE: successors disapeard, poor network")
		events.sleep(1)
		os.exit()
	end
	if #successors == 0 then
		max_no_succ = max_no_succ + 1
	end
	if max_no_succ >= 3 then
		log:print("SUICIDE: no successors ???")
		events.sleep(1)
		os.exit()
	end
end

------------------------------------------------------------------


events.run(function()
	--n.id = math.random(1, 2^m - 1)
	n.id = (math.random(1, 2^16) * math.random(1, 2^16)) - 1
	finger[1] = n
	local rdv = {}

	-- planetlab mode
	pl_mode = true

	if job then
		-- planetlab
		n.ip, n.port = job.me.ip, job.me.port

		--rdv = job.nodes[1]

		rdv = {ip = "192.42.43.30", port = math.random(20000, 20031)}
	else
		pl_mode = false
		if #arg < 4 then
			print("ip port rdv_ip rdv_port")
			os.exit()
		end
		n.ip, n.port, rdv.ip, rdv.port = arg[1], tonumber(arg[2]), arg[3], tonumber(arg[4])
		if arg[5] then
			--job = {position = tonumber(arg[5])}
		end
	end

	if not rpc.server(n, max_rpc_server) then
		log:error("Cannot bind port", n.port)
		return
	end
	--n.id = n.port

	log:print("START", n.id)

	if rdv.ip == n.ip and rdv.port == n.port then
		log:print("RDV start")
	else
		if pl_mode then
			--events.sleep(math.random(1, job.position * 2))

			--if job.position <= 8 then
			--events.sleep(10)
			--elseif job.position <= 8 + 32 then
			--events.sleep(170 + math.random(20))
			--elseif job.position <= 8 + 32 + 128 then
			--events.sleep(400 + math.random(50))
			--else
			--events.sleep(700 + math.random(100))
			--end

			if job.position <= 128 then
				events.sleep(math.random(100))
			else
				events.sleep(200 + math.random(300))
			end

		end
		log:print("Trying connecting RDV")
		while not join(rdv) do
			log:error("Join failed")
			events.sleep(math.random(10, 100))
		end
		log:print("RDV joined")
	end

	events.periodic(stabilize_timeout, stabilize)
	events.periodic(check_predecessors_timeout, check_predecessors)
	events.periodic(check_successors_timeout, check_successors)
	events.periodic(fix_fingers_timeout, fix_fingers)
	if not (rdv.ip == n.ip and rdv.port == n.port) then
		events.periodic(20, watchdog)
	end
	if not pl_mode then
		events.periodic(10, debug)
	else
		events.periodic(30, debug_pl)
		events.periodic(120, ressources_pl)
	end
end)
