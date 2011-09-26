--[[
       Splay ### v1.0.6 ###
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

--[[
This module is a coroutine dispatcher with an event system and handling socket
events in a particular way, to do, if possible, non busy waits.

Special kind of events (internal use only):

'event:send' socket [timeout]
'event:receive' socket [timeout]
'event:sleep'
'event:yield'
'event:kill'
'unlock:xx'

'event:yield' is not for waiting for a special event, it only permits to one
process to yield and to keep application reactivity.

Sockets events are handled particularly from the main loop because they are a
special case using a C routine.

- stats()

	Return a string showing threads, events, ...

## NOTES ##

events.yield() is good to give the hand to another thread, but if the current
thread is a loop that wait for a particular event, yield() is not a good choice
because the current thread will still be considered active. So even if there
are network threads, select() will not be used and the current thread called
again (busy loop). So if you need to wait for something, use wait() and fire().

At the moment, if the same events are fired multiple times, only the first one
is used, when you fire the next ones, you receive false because the "slot" is
already taken.

After each loop, all events are deleted, even if nobody has get them. There is
always somebody to get socket events.

There is no need to use coroutine.* from your application, you should use only
events.*.

An other implementation could have an event queue for each process. The process
will then take the next events it waits for. But the queue will fill with non
interesting events for that process. At this moment, we could have each process
to register on what events it is interested and have only them in the queue.

The timeout value is in (theorically) in microsecond (maybe system dependant).
The precision will be worse if you have an execution path that takes a lot of
time and don't yield (you must add a yield in each loop that may not wait for
something (wait() or doint some network things).

In some rare cases, a thread waiting on a 'classic' event and then on a socket
event can be executed 2 times consecutively if it is inserted in a socket queue
that have received the correct event. But in general case, the process are
executed in a round-robin mode.

In asynchronous protocols, the socket can be closed in the "send thread" while
already in the queue for the "receive thread". select() will not detect that
the socket is closed and wait forever. It's not a big problem since select()
is always called with the right timeout and another socket event will end the
wait immediatly. Then, the threads using the dead socket will see it is dead
and do the appropriate action.

--]]

local table = require"table"
local string = require"string"
local coroutine = require"coroutine"
local math = require"math"
local os = require"os"

local misc = require"splay.misc"
local socket = require"splay.socket"
local log = require"splay.log"

local debuglib = require"debug"

local next = next
local pairs = pairs
local type = type
local ipairs = ipairs
local print = print
local tostring = tostring
local unpack = unpack
local time = misc.time

module("splay.events")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Generic events dispatcher with timeouts using LuaSocket select()"
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

----------------------------------------[[ LOCKS ]]--

local lock_id = 0

-- Secure locks:
-- level 1: unlock if thread die on error
-- level 2: unlock if thread die
--
-- l = events.lock() => secure 1 (default)
-- l = events.lock(1) => secure 1
-- l = events.lock(2) => secure 2
-- l = events.lock(false) => no security

-- if secure locks, we unlock them when coroutine die
local locks = {}
local locked_by_thread = {}
local function lock_thread(lock_id, secure)
	local co = coroutine.running()
	if not locked_by_thread[co] then
		locked_by_thread[co] = {}
	end
	locked_by_thread[co][lock_id] = secure
	return true
end
local function unlock_thread(lock_id)
	local co = coroutine.running()
	if locked_by_thread[co] and locked_by_thread[co][lock_id] then
		locked_by_thread[co][lock_id] = nil
	end
end
local function unlock_die(co, err)
	if locked_by_thread[co] then
		for lock_id, s in pairs(locked_by_thread[co]) do
			if s == 2 or (s == 1 and err) then
				locks[lock_id]:unlock()
			end
		end
		locked_by_thread[co] = nil
	end
end

-- create a counting semaphore object, only use with o:lock() and o:unlock()
function semaphore(max, secure)
	if secure == nil then
		secure = 1
	end
	max = max or 1 -- 1 = lock
	lock_id = lock_id + 1
	local l = {
		id = lock_id - 1,
		inside = 0,
		max = max,
		secure = secure,
		lock = function(self, timeout)
			local end_t = math.huge -- end time
			if timeout then
				end_t = time() + timeout
			end
			if self.inside < self.max then
				self.inside = self.inside + 1
				if self.secure then
					return lock_thread(self.id, self.secure)
				else
					return true
				end
			else
				if end_t == math.huge then -- no timeout
					wait("unlock:"..self.id)
					return self:lock()
				else
					local now = time()
					while now < end_t and self.inside >= self.max do
						wait("unlock:"..self.id, end_t - now)
						now = time()
					end
					if self.inside < self.max then
						self.inside = self.inside + 1
						if self.secure then
							return lock_thread(self.id, self.secure)
						else
							return true
						end
					else
						return false
					end
				end
			end
		end,
		unlock = function(self)
			self.inside = self.inside - 1
			if self.secure then
				unlock_thread(self.id)
			end
			fire("unlock:"..self.id)
		end,
		-- aliases
		get = function(self, timeout) return self:lock(timeout) end,
		release = function(self) return self:unlock() end
	}
	if l.secure then
		locks[l.id] = l
	end
	return l
end

-- alias
function lock(secure) return semaphore(1, secure) end

-- DEPRECATED
function new_lock(...) return lock(...) end
function new_semaphore(...) return semaphore(...) end

local lock_f = {}
function synchronize(f, timeout)
	local name = tostring(f)
	if not lock_f[name] then
		lock_f[name] = lock()
	end
	if lock_f[name]:lock(timeout) then
		local r = {f()}
		lock_f[name]:unlock()
		return true, unpack(r)
	else
		return false, "timeout"
	end
end

----------------------------------------[[ END LOCKS ]]--

--[[ CODE ]]--

-- Mapping between name (tostring(coroutine) and object (coroutine)
local threads_ref = {}

-- for stats
local loop_count = 0
local select_count = 0
local mark_all_count = 0
local new_count = 0
local end_count = 0
local kill_count = 0

local new_threads = {}

--[[
Store the fired events and arguments.

events[event] = {arg = }
socket_events[event] = { sockets }
]]
local events = {}
local socket_events = {send = {}, receive = {}}

--[[
Store who is waiting for which event.

queue[event] = { threads }
socket_queue[event][socket] = { threads }
]]
local queue = {}
local socket_queue = {send = {}, receive = {}}

--[[
Store the time until this thread will wait for an event.

timeouts[thread] = end_time
]]
local timeouts = {}

--[[
Do final cleanup for threads that die, but do not remove from events queue.
]]
local function die(co, typ, event)
	local name = tostring(co)
	threads_ref[name] = nil

	if typ == "end" then
		unlock_die(co, false)
		end_count = end_count + 1
		l_o:notice(name.." DIE (end)")

	elseif typ == "error" then
		unlock_die(co, true)
		end_count = end_count + 1
		l_o:error(name.." DIE (error: "..tostring(event)..")")
		l_o:error(debuglib.traceback(co))
	
	elseif typ == "kill" then
		unlock_die(co, false)
		kill_count = kill_count + 1
		l_o:notice(name.." DIE (kill)")

	elseif typ == "selfkill" then
		unlock_die(co, false)
		kill_count = kill_count + 1
		l_o:notice(name.." DIE (self kill)")
	end
	return true
end

--[[
Execute a thread and, depending on the return, re-insert it into the event
queue, socket event queue (+ eventually timeout queue).

When calling this function, the coroutine must have been already
removed from his previous queue (except the timeouts one).

co: Thread to execute.
ret: Event argument, if there is one (ret.arg)
tm: boolean, true if we execute this thread because of a timeout.
]]
local function run_n_insert(co, ret, tm)

	local timeout, event, arg, arg2, s_arg, ok

	timeouts[co] = nil

	if ret then s_arg = ret.arg end

	--l_o:debug(tostring(co).." RUN with "..tostring(s_arg))
	
	if tm then
		ok, event, arg, arg2 = coroutine.resume(co, false, "timeout")
	else
		ok, event, arg, arg2 = coroutine.resume(co, true, s_arg)
	end

	if coroutine.status(co) == "suspended" and event ~= "event:kill" then
		
		-- socket events
		if event == "event:send" or event == "event:receive" then
			local sock = arg
			timeout = arg2
			if event == "event:send" then
				if not socket_queue["send"][sock] then
					socket_queue["send"][sock] = {}
				end
				socket_queue["send"][sock][#socket_queue["send"][sock] + 1] = co
			end
			if event == "event:receive" then
				if not socket_queue["receive"][sock] then
					socket_queue["receive"][sock] = {}
				end
				socket_queue["receive"][sock][#socket_queue["receive"][sock] + 1] = co
			end
		else
			-- normal events

			-- yield is the default action
			if not event then event = "event:yield" end

			timeout = arg
			if not queue[event] then queue[event] = {} end
			queue[event][#queue[event] + 1] = co
		end

		if timeout then timeouts[co] = timeout + time() end

		--if timeout then
			--l_o:debug(tostring(co).." SUSPEND wait "..tostring(timeout).."s for: "..tostring(event))
		--else
			--l_o:debug(tostring(co).." SUSPEND wait for: "..tostring(event))
		--end
		
	else
		if event == "event:kill" then
			die(co, "selfkill")
		else
			if not ok then
				die(co, "error", event)
			else
				die(co, "end")
			end
		end
	end
end

--[[
Say if some threads will be launched with the actual events.
Including network ones.
--]]
local function eligible_threads(all)
	-- "normal" events
	for event, _ in pairs(events) do
		if queue[event] then
			return true
		end
	end
	if all then
		-- "socket" events
		for event, sockets in pairs(socket_events) do
			for _, socket in pairs(sockets) do
				if socket_queue[event][socket] then
					return true
				end
			end
		end
	end
	return false
end

function count_threads()
	-- "new" threads
	local c = #new_threads
	-- "normal" events
	for event, _ in pairs(events) do
		if queue[event] then
			c = c + 1
		end
	end
	-- "socket" events
	for event, sockets in pairs(socket_events) do
		for _, socket in pairs(sockets) do
			if socket_queue[event][socket] then
				c = c + 1
			end
		end
	end
	return c
end

-- Check if there is some network threads.
local function network_threads()
	if next(socket_queue["receive"]) or next(socket_queue["send"]) then
		return true
	else
		return false
	end
end

-- Check if some threads have timeouted or the time of the next timeout.
local function have_threads_timeouted(ct)
	local min = math.huge
	for co, t in pairs(timeouts) do
		if t <= ct then
			return true
		else
			if t < min then
				min = t
			end
		end
	end
	return false, min
end

local function single_thread(th)
	local co
	new_count = new_count + 1
	if type(th) == "thread" then
		co = th
	else
		co = coroutine.create(th)
	end
	local name = tostring(co)
	threads_ref[name] = co
	l_o:notice(name.." NEW")
	new_threads[#new_threads + 1] = co
	return name
end

function thread(th)
	if type(th) == "table" then
		local r = {}
		for _, t in pairs(th) do
			r[#r + 1] = single_thread(t)
		end
		return r
	else
		return single_thread(th)
	end
end

-- Call a function periodically (only if the previous call is finished !)
-- Try only at time ticks (if the previous call is not finished, retry only
-- at the next schedule).
-- Use force to avoid the check of the previous call.
function periodic(time, handler, force)

	-- compatibility when the 2 first parameters were swapped
	if type(handler) == "number" then
		local tmp = time
		time = handler
		handler = tmp
	end

	return thread(function()
		local h, t
		while sleep(time) do
			l_o:notice("Periodic run "..tostring(handler).." ("..time..")")
			if not h or force or dead(h) then
				-- reset the backup
				if h and t and dead(h) then t = nil end

				if type(handler) == "table" then
					thread(handler)
				else
					h = thread(handler)
					-- we keep that copy to avoid it can be garbage collected and so
					-- the possibility that another thread to have the same name (h)
					t = threads_ref[h]
				end
			else
				l_o:warning("Periodic: "..tostring(h).." from "..tostring(handler)..
						" is not dead, we wait")
			end
		end
	end)
end

--[[
'th' is the thread name, not the coroutine object, so no reference is left
in the user env.
]]
local function single_kill(th)

	if threads_ref[th] then
		local co = threads_ref[th]

		timeouts[co] = nil

		for i, t in pairs(new_threads) do
			if t == co then
				table.remove(new_threads, i)
				return die(co, "kill")
			end
		end
		for event, threads in pairs(queue) do
			for i, t in pairs(threads) do
				if t == co then
					table.remove(threads, i)
					return die(co, "kill")
				end
			end
		end
		for event, els in pairs(socket_queue) do
			for socket, threads in pairs(els) do
				for i, t in pairs(threads) do
					if t == co then
						table.remove(threads, i)
						return die(co, "kill")
					end
				end
			end
		end

		-- We arrive here only if a thread kill himself...
		coroutine.yield("event:kill")
		return true
	else
		return nil, "not found"
	end
end

function kill(th)
	if type(th) == "table" then
		local r = {}
		for _, t in pairs(th) do
			r[#r + 1] = single_kill(t)
		end
		return r
	else
		return single_kill(th)
	end
end

function status(th)
	if type(th) == "string" then
		if threads_ref[th] then
			return coroutine.status(threads_ref[th])
		else
			return "dead"
		end
	else
		return coroutine.status(th)
	end
end

function dead(th)
	if not th then return true end -- behavior kept for compatibility
	if status(th) == "dead" then
		return true
	else
		return false
	end
end

-- Fire an event (don't yield)
function fire(event, ...)
	if not events[event] then
		--l_o:debug(tostring(coroutine.running()).." FIRE: "..tostring(event))
		events[event] = {arg = {...}}
		return true
	else
		l_o:notice(tostring(coroutine.running()).." ALREADY FIRED: "..tostring(event))
		return false
	end
end

function wait(event, timeout)
	--l_o:debug(tostring(coroutine.running()).." WAIT: "..tostring(event).." TM: "..tostring(timeout))
	local ok, r = coroutine.yield(event, timeout)
	if timeout then
		if ok then
			return ok, unpack(r)
		else
			return ok, r
		end
	else
		return unpack(r)
	end
end

function sleep(time)
	if not time or time < 0 then
		yield()
	else
		wait("event:sleep", time)
	end
	return true
end

function yield()
	return coroutine.yield()
end

-- When there is a select() timeout or no select at all, we do like if all
-- sockets have received an event to execute their threads.
local function mark_all()
	--l_o:debug("mark_all")
	mark_all_count = mark_all_count + 1
	for sock, _ in pairs(socket_queue["receive"]) do
		--l_o:debug("Artificial socket event receive: "..tostring(sock))
		socket_events["receive"][#socket_events["receive"] + 1] = sock
	end
	for sock, _ in pairs(socket_queue["send"]) do
		--l_o:debug("Artificial socket event send: "..tostring(sock))
		socket_events["send"][#socket_events["send"] + 1] = sock
	end
end

function run(th)

	-- shortcut for "main"
	if th then thread(th) end

	while true do

		loop_count = loop_count + 1
		--l_o:debug("loop "..loop_count)

		--[[ RUN NEW THREADS ]]--	
			
		-- We need to run the new threads (and the new threads generated by the new
		-- threads...)
		while #new_threads > 0 do
			run_n_insert(table.remove(new_threads, 1))
		end

		--[[ ADD THE "yield" EVENT ]]--
		events["event:yield"] = {}

		--[[ ADD NETWORK EVENTS (using select() or mark all as events) ]]--
		
		local status, ct = "timeout", time()
		local aet = eligible_threads()
		local htt, htt_time = have_threads_timeouted(ct)

		--l_o:debug("Status:", "aet", aet, "htt", htt, "htt_time", htt_time - ct)

		if next(socket_queue["receive"]) or next(socket_queue["send"]) then
			-- If there is already eligible threads or threads that have
			-- already timeouted, we don't use select() to not slow down the
			-- application.
			if not aet and not htt then
			-- to test without select() (active loop => 100% cpu):
			--if false then

				-- arrays for select()
				local sr, ss, socks_r, socks_s = {}, {}
				
				for sock, _ in pairs(socket_queue["receive"]) do
					sr[#sr + 1] = sock
				end
				for sock, _ in pairs(socket_queue["send"]) do
					ss[#ss + 1] = sock
				end

				if #sr + #ss < 1024 then -- workaround FD_SETSIZE
					-- don't seems to be necessary on recents systems
				
					--l_o:debug("pre-select()", #sr, #ss)

					select_count = select_count + 1

					local tt = htt_time

					if tt == math.huge then -- no timeout
						-- The additionnal timeout is needed for example if the only
						-- remaining threads is waiting for something that is already
						-- closed. The application will never end in this case without
						-- and additionnal security timeout.
						socks_r, socks_s, status = socket.select(sr, ss, 10)
					else

						tt = tt - ct

						-- If not true, it's because the time
						-- condition have_threads_timeouted() has changed
						-- between the previous call and here.
						-- UPDATE normally not possible anymore
						if tt > 0 then
							--l_o:debug("select()", tt)
							socks_r, socks_s, status = socket.select(sr, ss, tt)
						end
					end

					-- select() returned arrays are indexed in two ways:
					-- num => socket
					-- socket => num
					if status ~= "timeout" then
						-- transform results in events
						if socks_r then socket_events["receive"] = socks_r end
						if socks_s then socket_events["send"] = socks_s end
					else
						--l_o:debug("select() timeout", tt)
						mark_all()
					end
				else
					mark_all()
				end
			else
				mark_all()
			end
		else -- No network threads
			-- No eligible threads and no timeouts (but some waiting on)
			if not aet and next(timeouts) and not htt then
				-- Be careful to not call sleep() with a negative value
				if htt_time > ct then
					-- We will sleep a little (until the next timeout)
					--l_o:debug("Sleeping: "..tostring(htt_time - ct))
					socket.sleep(htt_time - ct)
				end
			end
		end

		--[[ STOP ]]--

		if not next(timeouts) and not eligible_threads(true) then
			l_o:notice("No threads to run with available events, we halt.")
			-- if we use select() when we are here there is at least one event
			-- (or we have something in timeout list).
			--l_o:debug("count threads: ", count_threads())
			break
		end

		--[[ RUN ]]--
		
		-- If not "timeout", that means that we have received a network event, that
		-- means too that there was nothing else to execute so we can safely skip
		-- this part.
		if status == "timeout" then

			-- "classic" events

			-- We need to duplicate and empty events tables before launching the
			-- threads.
			local events_tmp = events
			events = {}

			local tmp_queue = {}
			for event, threads in pairs(queue) do
				tmp_queue[event] = queue[event]
			end

			for event, threads in pairs(tmp_queue) do
				if events_tmp[event] then -- "event" has been fired

					-- We copy and remove all thread for that event
					local tmp = queue[event]
					queue[event] = nil
					--l_o:debug("Event removed: "..tostring(event))

					for _, thread in ipairs(tmp) do
						run_n_insert(thread, events_tmp[event])
					end

				else -- no "event" for these threads, but timeout ?

					for i, thread in ipairs(queue[event]) do
						if timeouts[thread] and timeouts[thread] <= time() then
							-- if an other timeouted thread is at the end
							-- position, it will be executed the next loop. In
							-- fact, in the worst case, we will execute only
							-- half of the timeouted thread in this loop.
							if i ~= #queue[event] then
								queue[event][i] = queue[event][#queue[event]]
							end
							queue[event][#queue[event]] = nil
							run_n_insert(thread, nil, true)
						end
					end
					if #queue[event] == 0 then queue[event] = nil end
				end
			end
		end

		-- "socket" events
		local event = "receive"
		local tmp_sock_ev = socket_events[event]
		socket_events[event] = {}

		for _, sock in pairs(tmp_sock_ev) do
			if socket_queue[event][sock] then

				-- We copy and remove all threads for that event
				local tmp = socket_queue[event][sock]
				socket_queue[event][sock] = nil
				--l_o:debug("Socket event removed: "..event..":"..tostring(sock))

				for _, thread in ipairs(tmp) do
					run_n_insert(thread)
				end
			end
		end

		local event = "send"
		local tmp_sock_ev = socket_events[event]
		socket_events[event] = {}

		for _, sock in pairs(tmp_sock_ev) do
			if socket_queue[event][sock] then

				-- We copy and remove all threads for that event
				local tmp = socket_queue[event][sock]
				socket_queue[event][sock] = nil
				--l_o:debug("Socket event removed: "..event..":"..tostring(sock))

				for _, thread in ipairs(tmp) do
					run_n_insert(thread)
				end
			end
		end
	end
end
-- DEPRECATED
loop = run

-- Useful in functions maybe called by TCP RPC so the caller get the
-- function feed-back and socket is closed properly before exiting.
function exit()
	thread(function()
		sleep(0.1)
		os.exit()
	end)
end

function infos()
	local count_ev = 0
	local count_sock_send_ev = 0
	local count_sock_recv_ev = 0
	local threads_ev = 1 -- the running thread is not waiting on anything...
	local threads_sock_send_ev = 0
	local threads_sock_recv_ev = 0

	for _, _ in pairs(events) do
		count_ev = count_ev + 1
	end
	for _, _ in pairs(socket_queue["send"]) do
		count_sock_send_ev = count_sock_send_ev + 1
	end
	for _, _ in pairs(socket_queue["receive"]) do
		count_sock_recv_ev = count_sock_recv_ev + 1
	end
	for _, threads in pairs(queue) do
		for _, _ in pairs(threads) do
			threads_ev = threads_ev + 1
		end
	end
	for _, threads in pairs(socket_queue["send"]) do
		for _, _ in pairs(threads) do
			threads_sock_send_ev = threads_sock_send_ev + 1
		end
	end
	for _, threads in pairs(socket_queue["receive"]) do
		for _, _ in pairs(threads) do
			threads_sock_recv_ev = threads_sock_recv_ev + 1
		end
	end

	return "Events: "..count_ev..
			" s: "..count_sock_send_ev.." r: "..count_sock_recv_ev.."\n"..
			"Threads: "..threads_ev..
			" s: "..threads_sock_send_ev.." r: "..threads_sock_recv_ev..
			" Total new: "..new_count.." end: "..end_count.." kill: "..kill_count.."\n"..
			"Loops: "..loop_count.." Selects: "..select_count.." Mark all: "..mark_all_count
end
