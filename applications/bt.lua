--[[
	Lua BT Client
	Copyright (C) 2006, 2007 Lorenzo Leonini - University of Neuchâtel
	http://www.splay-project.org
	splay [at] leonini (dot) net

http://wiki.theory.org/BitTorrentSpecification

LIMITATIONS
- A thread request a piece and wait to receive it before requesting another. We
do that to receive pieces of blocks in the right order.
- Different threads can try to get a same block. It's the good behavior in our
case because if a thread die it will never complete its block (even if 2 threads
download the same block, the hash is verified before to write the block on file)
- Works only for the torrents with one file.
--]]


--[[ Libraries ]]--
require"splay.base"
net = require"splay.net"
-- queue =
crypto = require"crypto"
http = require"socket.http"
bits = require"splay.bits"
benc = require"splay.benc"
queue = require"splay.queue"
to_int, to_string = misc.to_int, misc.to_string

log.global_level = 2

if job then
	log:info("SPLAY deployment")
	log:info("My position is: "..job.position)
	log:debug("> All jobs list:")
	for pos, n in pairs(job.nodes) do
		log:debug("Node "..pos.." ip: "..n.ip..":"..n.port)
	end
else
	job = {me = {ip = "127.0.0.1", port = 39939}}
end

--[[ Global vars ]]--
peer_id = "LUA01-----"..math.random(1000000000, 9999999999)
url = "http://cdimage.debian.org/debian-cd/4.0_r6/i386/bt-cd/debian-40r6-i386-CD-1.iso.torrent"

hash = '' -- hash of the torrent infos
torrent, tracker, peers = {}, {}, {}
nb_blocks, last_block_length = 0, 0

-- Data of the peers with we are connected.

-- Our blocks of data:
-- - array of partial block (then => disk)
-- - Bitfield array of our complete and verified blocks
-- - SHAs of each blocks (from the torrent)
blocks = {data = {}, bits = {}, shas = {}}

-- Stats
stats = {received = 0, sent = 0}

max_connect, max_accept = events.semaphore(20), 10

function count_blocks()
	local c = 0
	for _, j in pairs(blocks.bits) do
		if j == true then c = c + 1 end
	end
	return c
end

--[[ Retrieve the .torrent file, describing the torrent, hashes and tracker ]]--
function get_torrent(url)
	local r, code = http.request(url)
	if code == 404 or r == nil then return nil end

	-- We can't use benc.encode(torrent['info']) because the order can be
	-- different than on the real info string
	local a, b = string.find(r, "4:info")
	local t = string.sub(r, b + 1)
	t = string.sub(t, 1, string.len(t) - 1)

	return benc.decode(r), crypto.evp.new("sha1"):digest(t)
end

function html_escape(hash)
	local h_ue = ''
	for i = 1, string.len(hash), 2 do
		h_ue = h_ue..'%'..string.sub(hash, i, i+1)
	end
	return h_ue
end

-- Return tracker infos bdecoded and update our status
completed_sent = false
function get_tracker() -- use globals
	local event = nil
	local left = torrent.info.length - stats.received
	if left < 0 then left = 0 end
	local str = torrent.announce..
			"?info_hash="..html_escape(hash)..
			"&peer_id="..peer_id.."&port="..job.me.port..
			"&uploaded="..stats.sent.."&downloaded="..stats.received..
			"&left="..left
	if stats.received == 0 and stats.sent == 0 then event = "started" end
	if count_blocks() == nb_blocks and not completed_sent then
		completed_sent = true -- to send this event only once
		event = "completed"
	end
	if event then str = str.."&event="..event end

local res = http.request(str)
--print(res)

local ok, b = pcall(function() return benc.decode(http.request(str)) end)
if ok then
	return b
else
	return nil, res
end

	return benc.decode(http.request(str))
end

function send_headers(s) -- use globals
	local bp = "BitTorrent protocol"
	local h = string.char(string.len(bp))..bp..string.char(0, 0, 0, 0, 0, 0, 0, 0)
	for i = 1, string.len(hash), 2 do
		h = h..string.char(tonumber("0x"..string.sub(hash, i, i+1)))
	end
	-- It seems that some clients drop the peer_id
	return s:send(h..peer_id)
end

-- Send a bittorrent message, prefixing it with the length of the message
function send_msg(s, msg)
	if string.len(msg) >= 1 then
		log:print(tonode(s), "SEND "..code_to_name(string.byte(string.sub(msg, 1, 1))))
	end
	if peers[s] and peers[s].keep_alive then -- disable the keep_alive
		peers[s].keep_alive = false
	end
	return s:send(to_string(string.len(msg))..msg)
end

function send_keepalive(s)
	return send_msg(s, "")
end
function send_choke(s)
	peers[s].i_choked = true
	return send_msg(s, "\0")
end
function send_unchoke(s)
	peers[s].i_choked = false
	return send_msg(s, "\1")
end
function send_interested(s)
	peers[s].i_interested = true
	return send_msg(s, "\2")
end
function send_notinterested(s)
	peers[s].i_interested = false
	return send_msg(s, "\3")
end
function send_have(s, piece_number)
	return send_msg(s, "\4"..to_string(piece_number - 1))
end
function send_bitfield(s)
	return send_msg(s, "\5"..bits.bits_to_ascii(blocks.bits))
end
function send_request(s, index, begin, length)
	return send_msg(s, "\6"..to_string(index - 1)..to_string(begin - 1)..to_string(length))
end
function send_piece(s, index, begin, piece)
	return send_msg(s, "\7"..to_string(index - 1)..to_string(begin - 1)..piece)
end
function send_cancel(s, index, begin, length)
	return send_msg(s, "\8"..to_string(index - 1)..to_string(begin - 1)..to_string(length))
end
function send_port(s, port)
	return send_msg(s, "\9"..to_string(port, 2))
end

function assert_sock(s)
	local ori_send, ori_receive = s.send, s.receive
	s.send = function(...)
		return assert(ori_send(...))
	end
	s.receive = function(...)
		return assert(ori_receive(...))
	end
	s.recv_int = function(self, size)
		return to_int(self:receive(size or 4))
	end
end

function tonode(s)
	if peers[s] then
		return peers[s].ip..":"..peers[s].port
	else
		return tostring(s)
	end
end

function peer_fail(s)
	if peers[s] then
		if peers[s].ip then
			log:warning("Transmission problem with "..peers[s].ip..":"..peers[s].port)
		end
		peers[s] = nil
	end
end

function peer_connect(ip, port)
	local s = socket.tcp()
	s:settimeout(30)
	local ok = s:connect(ip, port)
	if ok then
		peer_run(s, true)
	else
		log:notice("Cannot connect peer: "..ip..":"..port)
	end
end

function peer_run(s, connect)
	s:settimeout(120)
	local ip, port = s:getpeername()
	if not ip then return end
	if pcall(function()
		peers[s] = {choked = true, interested = false, i_choked = true,
				i_interested = false, bitfield = {}, keep_alive = false,
				block_request = false, sent = 0, received = 0,
				requests = queue.new(), have = queue.new(),
				ip = ip, port = port}
		for i = 1, nb_blocks do
			peers[s].bitfield[i] = false
		end
		assert_sock(s)

		if connect then
			send_headers(s)
			log:notice(tonode(s), "Headers sent")
			s:receive(68)
			log:notice(tonode(s), "Headers received")
		else
			s:receive(68)
			log:notice(tonode(s), "Headers received")
			send_headers(s)
			log:notice(tonode(s), "Headers sent")
			send_bitfield(s)
			log:notice(tonode(s), "Bitfield sent")
		end

	end) then
		events.thread(function()
			if not pcall(function() peer_send(s) end) then
				peer_fail(s)
			end
		end)
		events.thread(function()
			if not pcall(function() peer_receive(s) end) then
				peer_fail(s)
			end
		end)
	else
		return peer_fail(s)
	end

	while peers[s] do events.sleep(5) end
end

function request_block(s, i)
	if blocks.bits[i] then return true end -- block already complete
	peers[s].block_request = true
	local start = string.len(blocks.data[i]) + 1
	local length = 2 ^ 14
	local block_length = torrent.info['piece length']
	if i == nb_blocks then
		block_length = last_block_length
	end
	if start + length - 1 > block_length then
		length = block_length - start - 1
	end
	log:print(tonode(s), "Request for block "..i.." at position "..start)
	return send_request(s, i, start, length)
end

function peer_send(s)
	local p = peers[s]
	local curr_block = nil
	local poss_blocks = {}
	
	send_unchoke(s)
	send_interested(s)

	while true do
		log:debug(tonode(s), "send loop")
		while not p.have.empty() do
			send_have(s, p.have.get())
		end
		if not p.i_choked and p.interested then
			while not p.requests.empty() do
				local r = p.requests.get()
				local f = assert(io.open("block_"..r.index, "r"))
				local data = assert(f:read("*a"))
				f:close()
				send_piece(s, r.index, r.begin,
						string.sub(data, r.begin, r.begin + r.length - 1))
				stats.sent = stats.sent + r.length
				p.sent = p.sent + r.length
			end
		end
		if not p.choked and p.i_interested and not p.block_request then
			if not curr_block or blocks.bits[curr_block] then -- curent block is done
				poss_blocks = {}
				for i = 1, nb_blocks do
					if peers[s].bitfield[i] and not blocks.bits[i] then
						poss_blocks[#poss_blocks + 1] = i
					end
				end
				if #poss_blocks >= 1 then
					curr_block = poss_blocks[math.random(1, #poss_blocks)]
					log:debug(tonode(s),
							"Blocks available: "..#poss_blocks..", we choose "..curr_block)
				else
					curr_block = nil
				end
			end
			if curr_block then
				request_block(s, curr_block)
			end
		end
		if p.keep_alive then
			send_keepalive(s)
		end
		events.wait(s, 5) -- All done, we wait for something...
	end
end

function peer_receive(s)
	while true do
		local mt = nil -- message type
		local len = s:recv_int()
		
		if len == 0 then -- keep_alive
			log:debug(tonode(s), "RECV keep_alive")
			peers[s].keep_alive = true
		else
			local mn = s:recv_int(1)
			log:debug(tonode(s), "RECV "..code_to_name(mn))

			if mn == 0 then -- choke
				peers[s].choked = true

			elseif mn == 1 then -- unchoke
				peers[s].choked = false

			elseif mn == 2 then -- interested
				peers[s].interested = true

			elseif mn == 3 then -- not interested
				peers[s].interested = false

			elseif mn == 4 then -- have
				local piece_number = s:recv_int() + 1
				peers[s].bitfield[piece_number] = true
				log:debug(tonode(s), "New piece: "..piece_number)

			elseif mn == 5 then -- bitfield
				local b = s:receive(len - 1)
				peers[s].bitfield = bits.ascii_to_bits(b, nb_blocks)
				log:debug(tonode(s), bits.show_bits(peers[s].bitfield))

			elseif mn == 6 then -- request
				local index, begin, length = s:recv_int() + 1, s:recv_int() + 1, s:recv_int()
				log:debug(tonode(s), 
						"Request for "..index.." at position "..begin.." (length: "..length..")")
				peers[s].requests.insert({index = index, begin = begin, length = length})

			elseif mn == 7 then -- piece
				local index, begin = s:recv_int() + 1, s:recv_int() + 1
				local piece = s:receive(len - 9)
				log:debug(tonode(s), "Piece of "..index.." received, starting at "..begin)
				stats.received = stats.received + string.len(piece)
				peers[s].received = peers[s].received + string.len(piece)

				peers[s].block_request = false
				-- that block can have been finished by another thread
				if not blocks.bits[index] then
					if string.len(blocks.data[index]) == (begin - 1) then
						blocks.data[index] = blocks.data[index]..piece
						local block_length = torrent.info['piece length']
						if index == nb_blocks then
							block_length = last_block_length
						end
						if string.len(blocks.data[index]) ==  block_length then
							local h = crypto.evp.new("sha1"):digest(blocks.data[index])
							if misc.hash_ascii_to_byte(h) == blocks.shas[index] then
								log:info(tonode(s), "Block "..index.." succefully received.")
								blocks.bits[index] = true
								local f = assert(io.open("block_"..index, "w"))
								assert(f:write(blocks.data[index]))
								f:close()
								for _, p in pairs(peers) do
									p.have.insert(index)
								end
							else
								log:warning(tonode(s),
										"Block "..index.." has not the right hash, remove.")
							end
							blocks.data[index] = nil -- freeing memory
						end
					else
						log:info(tonode(s), "Bad index: "..begin..", we wanted "..
								string.len(blocks.data[index])..")")
					end
				end

			elseif mn == 8 then -- cancel NOT IMPLEMENTED
				local index, begin, length = s:recv_int() + 1, s:recv_int() + 1, s:recv_int()

			elseif mn == 9 then -- port NOT IMPLEMENTED
				local port = s:recv_int(2)

			else
				log:warning(tonode(s), "Not understood command: "..code_to_name(mn))
				error("Unknown protocol")
			end
		end
		events.fire(s)
	end
end

function code_to_name(code)
	if code == 0 then return "choke"
	elseif code == 1 then return "unchoke"
	elseif code == 2 then return "interested"
	elseif code == 3 then return "not interested"
	elseif code == 4 then return "have"
	elseif code == 5 then return "bitfield"
	elseif code == 6 then return "request"
	elseif code == 7 then return "piece"
	elseif code == 8 then return "cancel"
	elseif code == 9 then return "port"
	else return tostring(code) end
end

function summary()
	log:print()
	log:print("#### Summary (mem: "..gcinfo().."ko) ###")
	log:print("Connected to: ")
	for s, p in pairs(peers) do
		local ip, port = s:getpeername()
		if p.choked then
			log:print(ip..":"..port.." choked ("..p.received.."-"..p.sent..")")
		else
			log:print(ip..":"..port.." unchoked ("..p.received.."-"..p.sent..")")
		end
	end
	log:print(count_blocks().." blocks completed.")
	local count = 0
	for i, data in pairs(blocks.data) do
		if string.len(data) > 0 then
			count = count + 1
		end
	end
	log:print(count.." blocks downloading.")
	log:print("Bytes received: "..stats.received)
	log:print("Bytes sent: "..stats.sent)
	log:print()
end

function update_tracker()
	while events.sleep(tracker.interval) do
		local t = get_tracker()
		if t then tracker = t end
	end
end

function connect_peers()
	if misc.size(peers) < 25 then
		local n = misc.random_pick(tracker.peers)
		-- We avoid IPv6 and ourself
		if string.match(n.ip, "^%d+\.%d+\.%d+\.%d+$") and n.port ~= job.me.port then
			for _, p in pairs(peers) do
				if p.ip == n.ip and p.port == n.port then return end
			end
			log:notice("Trying to connect peer: "..n.ip..":"..n.port)
			events.thread(function() peer_connect(n.ip, n.port) end)
		end
	end
end

events.loop(function()
	torrent, hash = get_torrent(url)
	if not torrent then
		log:error("Bittorrent file can't be received.")
		return
	end
	if torrent.info.files then
		log:error("We do not support multiple files torrent.")
		return
	end

	--for i, j in pairs(torrent.info) do print(i) end

	nb_blocks = math.ceil(torrent.info.length / torrent.info['piece length'])
	last_block_length = torrent.info.length % torrent.info['piece length']
	if last_block_length == 0 then last_block_length = torrent.info['piece length'] end

	log:info("Tracker: "..torrent.announce)
	if torrent.comment then log:info("Comment: "..torrent.comment) end
	log:info("Total file size: "..torrent.info.length)
	log:info("Pieces size: "..torrent.info['piece length'])

	for i = 1, nb_blocks do
		blocks.shas[i] = string.sub(torrent.info.pieces, (i - 1) * 20 + 1 , i * 20)
		blocks.bits[i] = false -- We have nothing ATM
		blocks.data[i] = ""
	end

	local t, err = get_tracker()
	if not t then
		log:error("Problem getting tracker", err)
		return
	end
	
	if t['failure reason'] then
		log:error("Tracker faillure: "..t['failure reason'])
		return
	end

	if net.server(job.me, peer_run, max_accept) then
		log:info("Listening on port "..job.me.port)
	else
		log:error("Error listening on port "..job.me.port)
		return
	end

	tracker = t

	for _, p in pairs(tracker.peers) do
		log:print(p.ip, p.port)
	end
	events.thread(update_tracker)
	events.periodic(15, summary)
	events.periodic(5, connect_peers)
end)
