-- THIS IS 'PAPER' IMPLEMENTATIO, see chord_p.lua for a robust one.


require"splay.base"
rpc = require"splay.rpc"
between, call, thread, ping = misc.between_c, rpc.call, events.thread, rpc.ping
n, predecessor, finger, timeout, m = {}, nil, {}, 5, 16
function join(n0) -- n0: some node in the ring
	finger[1] = call(n0, {'find_successor', n.id})
	call(finger[1], {'notify', n})
end
function closest_preceding_node(id)
	for i = m, 1, -1 do
		if finger[i] and between(finger[i].id, n.id, id) then 
			return finger[i]
		end
	end
	return n
end
function find_successor(id)
	--if between(id, n.id, (finger[1].id + 1) % 2^m) then
	-- en fait, quand on ne connait personne d'autre que nous, la condition sera
	-- fausse. on va ensuite forcement se renvoyer dans closest_preceding_node et
	-- ensuite rapeller find_successor sur nous (boucle sans fin)
	-- donc ici on va supposer que si finger 1 est nous, on ne connait personne
	-- d'autre et nous renvoyer directement.
	-- ceci se passe essentiellement quand on appelle fix_fingers, ensuite quand
	-- on est notifie, on remplace finger 1 par qqc de mieux...
	if finger[1].id == n.id or between(id, n.id, (finger[1].id + 1) % 2^m) then
		return finger[1]
	else
		local n0 = closest_preceding_node(id)
		return call(n0, {'find_successor', id})
	end
end
function stabilize()
	local x = call(finger[1], {'notify', n}) -- return predecessor
	if x and between(x.id, n.id, finger[1].id) then
		finger[1] = x -- new successor (will be notified next call to stabilize())
	end
end
function notify(n0)
	if n0.id ~= n.id and
			(not predecessor or between(n0.id, predecessor.id, n.id)) then
		predecessor = n0
	end
	if finger[1].id == n.id and n0.id ~= n.id then
		finger[1] = n0
	end
	return predecessor
end
function fix_fingers()
	refresh = (refresh and (refresh % m) + 1) or 1 -- 1 <= next <= m
	finger[refresh] = find_successor((n.id + 2^(refresh - 1)) % 2^m)
end
function check_predecessor()
	local p = predecessor
	-- we check that predecesor has not changed during our ping
	if p and not ping(p) and p == predecessor then
		predecessor = nil
	end
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

r_d = {}
function ring(me)
	if r_d[me.msg] then
		log.print("RING: "..me.msg.." already")
		call(me.origin, {'delivered', me})
	else
		r_d[me.msg] = me.msg
		log.print("RING: "..me.msg)
		me.count = me.count + 1
		if predecessor then
			thread(function()
				if not rpc.a_call(predecessor, {'ring', me}) then
					call(me.origin, {'next_error', me, n, Ls[1]})
				end
			end)
		else
			call(me.origin, {'delivered', me})
			log.print("RING: "..me.msg.." no finger[1]")
			return n.id.."\nempty leaf"
		end
	end
end

m_d = {}
function multicast(me)
	if not m_d[me.msg] then
		m_d[me.msg] = me.msg
		log.print("MULTICAST: "..me.msg)
		-- call for ourself !!!
		if me.call then
			log.print("calling "..me.call[1])
			thread(function() call(n, me.call) end)
		end
		-- to get all the nodes in an easy way...
		if me.all then
			thread(function() call(me.origin, {'delivered', n}) end)
		end
		for i = m, 1, -1 do
			if finger[i] then 
				thread(function() call(finger[i], {'multicast', me}) end)
			end
			if predecessor then
				thread(function() call(predecessor, {'multicast', me}) end)
			end
		end
	end
end

function display_finger()
	local out = ""
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

	print("_________________________________________")
	collectgarbage()
	print(gcinfo().." ko")
	print("ME: "..n.id)
	print(display_finger())
	print("_________________________________________")
	print()
end

------------------------------------------------------------------
n.id = math.random(1, 2^m)
finger[1] = n
if job then
	n.ip, n.port = job.me.ip, job.me.port
	--thread(function() join({ip = "192.42.43.42", port = 20000}) end)
	if job.position > 1 then
		thread(function()
			events.sleep(10)
			join(job.nodes[1])
		end)
	end
else
	n.ip, n.port = "127.0.0.1", 20000
	if arg[1] then n.ip = arg[1] end
	if arg[2] then n.port = tonumber(arg[2]) end
	if not arg[3] then
		print("RDV")
	else
		print("JOIN")
		thread(function() join({ip = arg[3], port = tonumber(arg[4])}) end)
	end
end
rpc.server(n.port)
events.periodic(stabilize, 1)
events.periodic(check_predecessor, timeout)
events.periodic(fix_fingers, 1)
events.loop()
