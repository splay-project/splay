--[[
	Splayd
	Copyright 2011 - Valerio Schiavoni (University of Neuchâtel)
	http://www.splay-project.org
]]

--[[
This file is part of Splayd.

Splayd is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

Splayd is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
Splayd.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[

USAGE:

socket = require"socket.core"
ts = require"splay.topo_socket"
ts.init(settings)
socket = ts.wrap(socket)
require"splay.base"

The settings table is provided by the controller: for each node in the network, 
provides the delays and the max_bandwidth to use by the current node toward each 
other node.

NOTE
The initialization of the ts socket must be done strictly *before* requiring splay.base
otherwise the configuration will be discarded.
 
I cannot require splay.events to rely on the Splay timing tools. 
To have a given send/receive wait, it will have to rely on more
low-level stuff, directly handing coroutines. 

The in_delay value given in the config is divided by 2 due to the way
the RPC encoding is done in splay. This is problematic if not using
RPC calls between (aka raw sockets), as observed latencies would result
in X/2 as those specified in config.

]]
local base = _G
local coroutine=require"coroutine"
local string = require"string"
local misc=require"splay.misc"
local log = require"splay.log"
local tb=require"splay.token_bucket" --bandwidth-shaping tool
local tree=require"splay.tree" --to model flow tree and dynamic BW adjustments
local tostring = tostring
local setmetatable = setmetatable
local type=type
local pairs=pairs
local print=print
local time=os.time
local date=os.date
local getenv=os.getenv
local tonumber=tonumber
local assert=assert
local math=require"math"
local table = table
local unpack=unpack
local assert = assert

module("splay.topo_socket")


--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

in_delay=0
out_delay=0
bw_out=nil
bw_in =nil
--token_bucket_upload   = nil 
--token_bucket_download = nil 
TB_RATE = 1
MAX_BLOCK_SIZE=1024*1024 --1024kilobits/128kilobytes
do_chopping=false
global_topology=nil
current_downloads={}
current_downloads_counter=0
raw_topology=nil
pos=nil
--[[
The dynamic_tree represents the tree rooted at this node. It is initialized
from the static model sent by the controller. The weights on the edges
are initialized to zero. For every transfer in progress, the weigth on the edges
are incremented by one. For every edge used by more than one transfer, a conflict
resolution process allocates the fair amount of bandwidth to each one.
The tree is a n-ary tree, where each node can have 0 to N subtrees. 
]]--
dynamic_tree=tree.new()
BW_SHARING="fair"

--PROTOCOL OVERHEADS, values from http://sd.wareonearth.com/~phil/net/overhead/ 
TCP_OVERHEAD = 0.949285
UDP_OVERHEAD = 0.957087
--[[ CONFIG ]]--
local init_done = false
function init(settings,nodes,topology,my_pos)
		if not init_done then
				init_done = true	
				pos=my_pos	
				if not settings then return false, "no settings" end
				if settings.in_delay~=nil and settings.in_delay>0 then	
					in_delay=(settings.in_delay/2) --the /2 is to hack the splay RPC encoding
				end 
				if settings.out_delay~=nil and settings.out_delay >0 then
					out_delay=(settings.out_delay/2)
				end
				if settings.MAX_BLOCK_SIZE~=nil then
					if settings.MAX_BLOCK_SIZE*1024>256*1024 then
						l_o:warning("MAX_BLOCK_SIZE is too big. Max allowed is <= ",128*1024)
					else
						MAX_BLOCK_SIZE=settings.MAX_BLOCK_SIZE*1024
					end
				end
				if settings.CHOPPING==true then
					do_chopping=true
				end
				if settings.BW_SHARING~=nil and
					(settings.BW_SHARING=="fair" or settings.BW_SHARING=="unfair") then
					BW_SHARING=settings.BW_SHARING
				end
				if settings.TB_RATE~=nil then
					TB_RATE = settings.TB_RATE
				end
				
				
				local total_bw_out=0
				if topology then
					raw_topology=misc.dup(topology) --save it for later
					global_topology={}
					for k,t in pairs(topology) do
						--l_o:debug("Topology infos (pos:"..k..",ip:"..nodes[tonumber(k)].ip..",port:"..nodes[tonumber(k)].port.."):")
						for dst,infos in pairs(t) do
							--l_o:debug("Accessing nodes["..dst.."] ")
							if nodes[tonumber(dst)]==nil then
								l_o:error("Can't read topology informations for node in pos:",dst)
								break
							end
							--l_o:debug(nodes[tonumber(dst)].port)
							--l_o:debug(nodes[tonumber(dst)].ip)
						
						    if tonumber(infos[3][1])==my_pos then --keep only local topology informations (other infos can be used for router congestion emulation,requires changing datastructure)
								--l_o:debug("raw path: ", table.concat(infos[3]," "))
						    	--l_o:debug("kbps for hops in path: ", table.concat(infos[4]," "))
						    	--l_o:debug("\t",nodes[tonumber(dst)].ip..":"..nodes[tonumber(dst)].port, "delay(ms):"..infos[1], "bw(kbps):"..infos[2].." (Kbps):"..infos[2]/8,"(bytes):"..infos[2]*128)
						    	--infos[2] is in kbps, convert in bytes before initializing bucket
						    	local bucket=tb.new(infos[2]*128, infos[2]*128 )
						    	local dst_n=nodes[tonumber(dst)]
						    
								--[[key: the ip:port of the node, value: topology-related infos to reach key
								global_topology[k][1]=out-delay to k
								global_topology[k][2]=max-bw to k (without path conflicts)
								global_topology[k][3]=token-bucket initialized for this point-to-point transfer
								global_topology[k][4]=the path from current node to dst, given as integers (int=position in job.nodes)
								global_topology[k][5]=the max capacity of the phisical links on the path to dst, given in kilobits/s (static)
								global_topology[k][6]=dynamically adjusted value for the outgoing bw. Initially set to g[k][5] but adjusted at runtime
								global_topology[k].position=the position of this node in the original list of nodes (TODO: churn?)
								--]]
								global_topology[dst_n.ip..":"..dst_n.port]={infos[1],infos[2]*128,bucket,infos[3],infos[4],infos[2]*128,position=tonumber(dst)} --out-delay,out-bw,token_bucket,full-path,kbps_hops,current-out-bw
								total_bw_out=total_bw_out+infos[2]
								--build the tree rooted at this node based on the paths received by the controller.
								add_nodes_to_tree(infos[3],infos[4])				
							end
						end
					end
				end	
				
				--l_o:debug("Tree size: ", dynamic_tree.size())
				--for k,v in pairs(dynamic_tree.nodes) do
				--	l_o:debug("Height of "..k.." => ", dynamic_tree.height_node(dynamic_tree.getnode(k)))
				--end
				
				bw_out=settings.bw_out or 1024*1024*1024 -- by default 1Gb/sec, unlimited
				bw_in=settings.bw_in or 1024*1024*1024 -- by default 1Gb/sec, unlimited
			
				--l_o:debug("Settings:")
				--l_o:debug("in_delay:", in_delay)
				--l_o:debug("out_delay:", out_delay)
				--l_o:debug("bw_out (max):", (bw_out/1024),"(Kb/s)")
				--l_o:debug("bw_in (max):", (bw_in/1024),"(Kb/s)")
				--l_o:debug("MAX_BLOCK_SIZE:",misc.bitcalc(MAX_BLOCK_SIZE).kilobits.."Kb/"..misc.bitcalc(MAX_BLOCK_SIZE).kilobytes.."KB")
				--l_o:debug("Position:", my_pos)
				
				return true
		else
			return false, "init() already called"
		end
end
function id_from_position(po)
	for k,v in pairs(global_topology) do
		--l_o:debug("k="..k,"v="..v.position,"po="..po,type(v.position),type(po))
		if tonumber(po)==v.position then return k end
	end
	return nil
end
--add the nodes in the path to the dynamic_tree.
function add_nodes_to_tree(path,link_capacities)
	--l_o:debug("Adding nodes to tree from path:", table.concat(path,"-"))
	--l_o:debug("Hops capacities				 :", table.concat(link_capacities,"-"))
	local root= path[1]
	dynamic_tree.addnode(root,nil) --the root	
	for i=2,#path do
		dynamic_tree.addnode(path[i], dynamic_tree.getnode(path[i-1]), link_capacities[i-1]*128)		
	end
end
--store all the local graph events 
tree_events={}
last_event_idx=0
--when a new upload is starting toward 'node', the tree has to be
--marked accordingly to check for contention of shared links with 
--other streams.
function mark_stream_to(node)
	local pos_node=tostring(global_topology[node].position)
	--l_o:debug("Marking stream to ",node, "position:",pos_node)
	local n=dynamic_tree.getnode(pos_node)
	dynamic_tree.incrementflowto(n,raw_topology)
	last_event_idx=last_event_idx+1
	local plus_ev="+ "..table.concat(dynamic_tree.pathtoroot(n)," ")
	tree_events[last_event_idx]=plus_ev	
	--l_o:debug("Last Added event:", plus_ev)	
	adjust_rates()
	--l_o:debug("TB Rates adjusted")	
end
--when an upload toward 'node' finishes, the tree has to be
--marked accordingly to check for contention of shared links with 
--other streams.
function unmark_stream_to(node)
	local pos_node=tostring(global_topology[node].position)
	--l_o:debug("UnMarking stream to ",node, "position:",pos_node)
	local n=dynamic_tree.getnode(pos_node)
	dynamic_tree.decrementflowto(n, raw_topology)	
	last_event_idx=last_event_idx+1
	local less_ev="- "..table.concat(dynamic_tree.pathtoroot(n)," ")
	tree_events[last_event_idx]=less_ev
	--l_o:debug("Last Added event:", less_ev)
	adjust_rates()
	--l_o:debug("TB Rates adjusted")
end

function handle_tree_change_event(tevent)
	if tevent[1]=="+" then f=dynamic_tree.incrementflowfromto
	elseif tevent[1]=="-" then f=dynamic_tree.decrementflowfromto
	else error("Cannot handle tree_change_event:", table.concat(tevent," ")) end
	local flowdest=tevent[#tevent]
	table.remove(tevent,1)
	local flowsource=tevent[1]
	for i=#tevent,2,-1 do
		--actual parameters are in reverse order because the for-loop iterates backwardly
		f(dynamic_tree.getnode(tevent[i]),dynamic_tree.getnode(tevent[i-1]),flowdest, flowsource, raw_topology)		
	end
	adjust_rates()
	--l_o:debug("TB Rates adjusted")
end

--adjust BW rates to LEAVES nodes
function adjust_rates()
	local leaves=dynamic_tree.leaves()
	for leaf,v in pairs(leaves) do
		local lid=id_from_position(leaf)
		local current_rate_to_leaf= global_topology[lid][6]		
		--l_o:debug("[adjust-rates] Current rate to leaf "..lid,current_rate_to_leaf, "Kb:"..misc.bitcalc(current_rate_to_leaf).kilobits,"Mb:"..misc.bitcalc(current_rate_to_leaf).megabits )
		local max_rate_to_leaf= global_topology[lid][2]	
		--l_o:debug("[adjust-rates] MAX     rate to leaf "..lid,max_rate_to_leaf,"Kb:"..misc.bitcalc(max_rate_to_leaf).kilobits,"Mb:"..misc.bitcalc(max_rate_to_leaf).megabits )
		local max_bw_available_to_bw
		
		local args={lid=lid,leaf=leaf,topology=global_topology,raw_topology=raw_topology}
		
		if  BW_SHARING =="fair" then
			max_bw_available_to_bw= dynamic_tree.maxavailbwto(dynamic_tree.getnode(leaf),args)
		--	l_o:debug("[adjust-rates] MAX BW available to leaf "..lid, max_bw_available_to_bw, "Kb:"..misc.bitcalc(max_bw_available_to_bw).kilobits,"Mb:"..misc.bitcalc(max_bw_available_to_bw).megabits )	
		elseif BW_SHARING =="unfair" then
			max_bw_available_to_bw= dynamic_tree.unfairmaxavailbwto(dynamic_tree.getnode(leaf),args)
		end
		local max_rate_allowed= math.min( max_rate_to_leaf, max_bw_available_to_bw)	
		--l_o:debug("[adjust-rates] MAX rate allowed to leaf "..lid, max_rate_allowed )	
		--TODO to distinguish TCP/UDP and associated overheads the DCM protocol must ship the type of
		--the traffic associated with a given flow. for now let's stick with TCP...
		--TODO consider TCP-ReverseACK load on revese link
		global_topology[lid][6]=max_rate_allowed*TCP_OVERHEAD 			
	end
end



--[[
 Create a Topology emulation layer around a true UDP socket.
]]
local function udp_sock_wrapper(sock)

	local new_sock = {}

	-- This socket is called with ':', so the 'self' refer to socket but, in
	-- the call, self is the wrapping table, we need to replace it by socket.
	local mt = {
		__index = function(table, key)
			return function(self, ...)
				--l_o:debug("udp."..key.."()")
				return sock[key](sock, ...)
			end
		end,
		__tostring = function()
			return "#TS (UDP): "..tostring(sock)
		end}

	setmetatable(new_sock, mt)
	
	-- Restricted methods related to incoming/outgoing datas --

	if sock.receive then
		new_sock.receive = function(self, ...)
			if in_delay>0 then
				local w0=misc.time()
				local ok, r = coroutine.yield("event:sleep", in_delay) --tied to splay "event:sleep" event
				local w1=misc.time()
				l_o:debug("udp.receive(), effective in_delay:",w1-w0)
			end
			local data, msg = sock:receive(...)
		
			--l_o:debug("receive",data,msg)
			accept_datagram=true
		
			if not accept_datagram then
				return nil,'timeout'
			else
				return data,msg
			end
			
		end
	end

	if sock.receivefrom then
		new_sock.receivefrom = function(self, ...)
			if in_delay>0 then
				local w0=misc.time()
				local ok, r = coroutine.yield("event:sleep", in_delay) --tied to splay "event:sleep" event
				local w1=misc.time()
				l_o:debug("udp.receivefrom(), effective in_delay:",w1-w0)
			end
		
			local data, ip, port = sock:receivefrom(...)
		
			accept_datagram=true
			
			if not data then
				return nil,'timeout'
			end
			
			if not accept_datagram then
				return nil,'timeout'
			else
				return data, ip, port
			end
		end
	end
	
	if sock.send then
		new_sock.send = function(self, data)
			local delay=out_delay --default value, specific for this node and for any outgoing message
			local bw=bw_out
			local peer_ip,peer_port=self:getpeername()
			--l_o:debug("Socket peername:",peer_ip..":"..peer_port)		
			local dst=peer_ip..":"..peer_port
			if global_topology[dst]~=nil then
				--l_o:debug("Emulating connection with delay and kbps:",global_topology[dst][1],global_topology[dst][2])
				delay=tonumber(global_topology[dst][1]/1000.0)
				--l_o:debug("Delay toward "..dst.." "..delay.."(s)")
				--convert kbps to Kbps
				bw=global_topology[dst][2]/8	
				--l_o:debug("BW toward (kbps/Kbps)"..dst,global_topology[dst][2],bw)	
			end
			--l_o:debug("udp.send()")
			if delay>0 then
				local w0=misc.time()
				local ok, r = coroutine.yield("event:sleep", delay) --tied to splay "event:sleep" event
				local w1=misc.time()
				local eff_delay=w1-w0
				l_o:debug("udp.sendto() ideal delay:",delay," effective delay:",eff_delay,"RATIO EFF/IDEAL:",(eff_delay/delay))
			end
			return sock:sendto(data)
		end
	end

	if sock.sendto then
		
		new_sock.sendto = function(self, data, ip, port)
			--l_o:debug("udp.sendto()")
			--l_o:debug("sendto,  "..ip..":"..port)
			local delay=out_delay --default value, specific for this node and for any outgoing message
			local bw=bw_out
			local dst=ip..":"..port
			local dest_tb=nil -- token_bucket for the partner
			if global_topology[dst]~=nil then  --on UDP, ack packets are sent on different PORT 			
				--l_o:debug("Emulating connection with delay and kbps:",global_topology[dst][1],global_topology[dst][2])
				delay=tonumber(global_topology[dst][1]/1000.0)
				--l_o:debug("Delay toward "..dst.." "..delay.."(s)")
				--convert kbps to Kbp/s
				bw=global_topology[dst][2]/8	
				--l_o:debug("BW toward (kbps/Kbps)"..dst,global_topology[dst][2],bw)
				
				dest_tb=global_topology[dst][3]
				local data_bytes=#data
				local expected_upload_time=(data_bytes/1024)/bw --in seconds

				--l_o:debug(">",ip,port,"BW (Kbps)=",bw,"data Kbytes=",data_bytes/1024)
				
				local ris, err = nil
				local sent=false
				--local w0=misc.time()
				--local ok, r = coroutine.yield("event:sleep", expected_upload_time)
				--ris,err=sock:sendto(data,ip,port)
				while not sent do --
					--if there are enough tokens, send it, otherwise wait for the next round
					if dest_tb.consume(data_bytes) then --try to consume #(data_bytes) token
						--l_o:debug("Got tokens:",dest_tb.get_tokens())	
						--got tokens, now emulate latency before sending over the wire
						if delay >0 then
							local w0=misc.time()
							--tied to splay "event:sleep" event
							local ok, r = coroutine.yield("event:sleep", delay)
							local w1=misc.time()
							local eff_delay=w1-w0
							l_o:debug("udp.sendto() ideal delay:",delay," effective delay:",eff_delay,"RATIO EFF/IDEAL:",(eff_delay/delay))
						end
						ris,err=sock:sendto(data,ip,port)
						sent=true
					else
						l_o:debug("Not enough tokens, available: ",dest_tb.get_tokens(),"required=",data_bytes)
					end				
					local ok, r = coroutine.yield("event:sleep", 1) --wait next clock tic for more tokens...					
				end
				--local w1=misc.time()
				--local eff_upload_time=w1-w0
				--l_o:debug("udp.sendto() ideal upload_time:",expected_upload_time," effective_upload_time:",eff_upload_time,"RATIO UP_EFF/UP_IDEAL:",(eff_upload_time/expected_upload_time))
				return ris, err
			else
				--no mappings in the global_topology, send rightaway
			 	local ris, err=sock:sendto(data,ip,port)
			 	return ris,err
			end			
			
		end
	end
	
	--this function doesn't generate any traffic on the network
	--turns the socket from unconnected to connected, to gain 30% perfs
	if sock.setpeername then
		new_sock.setpeername = function(self, ip, port)
			return sock:setpeername(ip, port)
		end
	end	
	--this function doesn't generate any traffic on the network
	if sock.setsockname then
		new_sock.setsockname = function(self, address, port)
			return sock:setsockname(address, port)
		end
	end
	--this function doesn't generate any traffic on the network
	if sock.close then
		new_sock.close = function(self)
			sock:close()
		end
	end
	return new_sock
end

--[[
 Create a Topology emulation layer around a true tcp socket.
]]
local function tcp_sock_wrapper(sock)
	
	--[[
	Store non conformant packets with the appropriate indexes to know
	what to send in the next clock tic. This is relevant for the 
	token-bucket algorithm.
	--]]
	local outgoing_non_conformant_datas={}
	
	local new_sock = {}
	
	-- This socket is called with ':', so the 'self' refer to socket but, in
	-- the call, self is the wrapping table, we need to replace it by socket.
	local mt = {
		__index = function(table, key)
			return function(self, ...)
				--l_o:debug("tcp."..key.."()")
				return sock[key](sock, ...)
			end
		end,
		__tostring = function()
			return "#TS (TCP): "..tostring(sock)
		end}

	setmetatable(new_sock, mt)
	
	if sock.receive then
		--[[
		The idea would be to see how much data was received during the last
		scheduled 'receive', and yield the coroutine for a given amount of
		seconds so that the observed effect would be a limited-rate download
		speed.
		]]
		new_sock.receive = function(self, pattern, prefix,start_time)			
			--l_o:debug("tcp.receive()")
			if in_delay>0 then
				local w0=misc.time()
				local ok, r = coroutine.yield("event:sleep", in_delay)
				local w1=misc.time()
				--l_o:debug("tcp.receive(), effective in_delay:",w1-w0)
			end			
			
			--l_o:debug("Receiving data from", self:getpeername())
			
			local data, msg, partial = sock:receive(pattern, prefix)
			return data, msg, partial
		end
	end
	
	if sock.send then
		new_sock.send = function(self, data, start, stop)
			--l_o:debug("tcp.send()",data,start,stop)			
			local delay=out_delay 

			local peer_ip,peer_port=self:getpeername()
			--l_o:debug("Socket peername:",peer_ip..":"..peer_port)		
			local dst=peer_ip..":"..peer_port
			--when server  socket sends back ACK on splay RPC, the destination is 
			--the client_socket which is not known in advance for TCP or default UDP, answer sent back at raw speed.
			if global_topology[dst]==nil then
			    l_o:debug("No BW shaping infos to ",dst," (client socket?)")
			    n, status,last = sock:send(data,start, stop) 
			    l_o:debug("returning ",#data,status,last)
			    return #data,status,last
			end
			if global_topology[dst]~=nil then
				l_o:debug("Emulating connection with delay and byte/s:",global_topology[dst][1],global_topology[dst][6])
				--[[
				The *2 factor is because we cannot emulate the delay on the backlink due to the 
				nature of the TCP sockets.
				--]]
				delay=tonumber(global_topology[dst][1]/1000.0) * 2 
				--l_o:debug("Delay toward "..dst.." "..delay.."(ms)")							
				if delay>0 then
					local w0=misc.time()
					local ok, r = coroutine.yield("event:sleep", delay) --tied to splay "event:sleep" event
					local w1=misc.time()
					local eff_delay=w1-w0
				--	l_o:debug("tcp.send(), effective delay:",eff_delay,"RATIO_EFF_DELAY:",(eff_delay/delay))
				end
			end			
			local data_bytes=#data
			l_o:debug("Total bytes to send:", data_bytes)					
			local n=start			
			--l_o:debug("Start index: ", n)			
			--START BANDWIDTH LIMITATION			
			if global_topology[dst]~=nil then 
				mark_stream_to(dst) --useful for DCM
			end
			local tbu=global_topology[dst][3]  --the token_bucket_upload toward the dst node				
			while data_bytes>0 do		
				--[[
				size is the smaller amount of data between the remaining data to sent and 
				the maximum allowed by the per-destination's token bucket at each round.
				The value is given in bytes PER second. Adjust it with the TB_RATE in case of finer-grain precision.
				]]		
				local size = math.min(data_bytes,(global_topology[dst][6])) --adjusted at runtime if needed				
				l_o:debug("Block size: ",misc.bitcalc(size).bytes.." bytes",misc.bitcalc(size).kilobytes.."KB",misc.bitcalc(size).megabits.."Mb")	
				if tbu.consume(size) then
					tbu.get_tokens()
				
					if do_chopping then
						--l_o:debug("Chopping. Datasize:",misc.bitcalc(size).kilobits,"Kb", "Chopsize:",misc.bitcalc(MAX_BLOCK_SIZE).kilobits,"Kb")
						local chops_counter=0  
						while size > 0 do
							l_o:debug("Remaining data to send bytes: "..size, "Kb: "..misc.bitcalc(size).kilobits,"current-chop:", chops_counter)
							local s=n --beginning of this block
							--l_o:debug("Block start index:", s)
							local block_to_send= math.ceil(math.min(MAX_BLOCK_SIZE, size))
							l_o:debug("SIZE of BLOCK block-to-snd:", block_to_send)
							l_o:debug("SEND INDICES", "i: ".. n, "j: "..n+block_to_send)									
							n, status,last_byte_sent = sock:send(data,n,n+block_to_send)
							if n~=nil then 
								--SEND successful, update counters and block segment index
								chops_counter=chops_counter+1
								n=n+1+block_to_send  --RESTORE TO IN CASE OF PANIC: n+1
								size=size-block_to_send
								data_bytes=data_bytes-block_to_send 
								l_o:debug("Data sent at last tic bytes:", block_to_send," remaining to send:", data_bytes)
							else
								if last_byte_sent~=nil then
									n=last_byte_sent+1
									data_bytes=data_bytes-(last_byte_sent-s)
									size=size-(last_byte_sent-s)
									l_o:debug("Error sending chop "..chops_counter.." :", status, "last sent:",last_byte_sent,"still to send in chop :",size)
								else
									l_o:debug("Error sending data:", status, "last sent:",last_byte_sent,"still to send:",data_bytes)
								end
							end							
						end
						--l_o:debug("chops_counter sent:", chops_counter)
					else
						--l_o:debug("No Chopping. Datasize:",misc.bitcalc(size).kilobits.."Kb")
						local s=n
						--no more than #data, at most #size bytes sent
						local block_to_send=math.ceil(math.min(data_bytes,size))
						l_o:debug("No Chopping.tcp.send() parameters [i,j]:",n,n+block_to_send)
						--n, status,last = sock:send(data,n,n+size)
						n, status,last = sock:send(data,n,n+block_to_send)						
						l_o:debug("No Chopping, sock.send() n:",n,"status:",status,"last",last)
						if n~=nil then  
							n=n+block_to_send+1 --RESTORE TO IN CASE OF PANIC: n+1
							data_bytes=data_bytes-size 
							l_o:debug("Data sent at last tic:", size, (size/1024).."Kb")
						else
							n=last+1 --resend from here
							data_bytes=data_bytes-(last-s)
							l_o:debug("Error sending data:", status, "last sent:",last,"still to send:",data_bytes)
						end
					end
					if data_bytes>0 then
						l_o:debug("Remaining to send: ",misc.bitcalc(data_bytes).kilobits.." Kb", "("..((data_bytes/#data)*100).." % sent)")
					end
				else
					l_o:debug("Not enough tokens to send "..size.." bytes. Available tokens: ",tbu.get_tokens())
				end	
				if data_bytes>0 then		
				  local ok, r = coroutine.yield("event:sleep", TB_RATE) --wait next clock tic for more tokens...TODO: how to do without coroutine ? 
				end
			end 			
			unmark_stream_to(dst)	
			--END BANDWIDTH LIMITATION
			
			--n, status,last = sock:send(data,start, stop) --use to debug vanilla
			--l_o:debug("returning ",#data,status,last)
			return #data,status,last
		end
	end

	if sock.connect then
		new_sock.connect = function(self, ip, port)
			--l_o:debug("tcp.connect("..ip..", "..tostring(port)..")")
			assert(ip,"IP to sock:connect(..) is nil")
			assert(port,"Port to sock:connect(..) is nil")
			--[[
			With TCP, 3-way handshake to be considered to compute the delays.
			]]--
			local dst=ip..":"..port
			if global_topology[dst]~=nil then
				--[[
				The *2 factor is because we cannot emulate the delay on the backlink due to the 
				nature of the TCP sockets.
				--]]
				delay=tonumber(global_topology[dst][1]/1000.0)
				--l_o:debug("Delay toward "..dst.." "..delay.."(ms)")
			
				if delay~=nil and delay>0 then
					local w0=misc.time()
					local ok, r = coroutine.yield("event:sleep", delay) --tied to splay "event:sleep" event
					local w1=misc.time()
					local eff_delay=w1-w0
					--l_o:debug("tcp.connect(), effective delay:",eff_delay,"RATIO_EFF_DELAY:",(eff_delay/delay))
				end
			end
			local s, m = sock:connect(ip, port)
			return s, m
		end
	end
	
	--this function doesn't generate any traffic on the network
	if sock.bind then
		new_sock.bind = function(self, address, port, backlog)
			--l_o:debug("tcp.bind("..address..", "..tostring(port)..")")
			return sock:bind(address, port, backlog)
		end
	end

	if sock.close then
		new_sock.close = function(self)
			--l_o:debug("tcp.close()")

			if not sock:getsockname() then
				l_o:notice("Closing an already closed socket.")
			else
				--l_o:debug("Peer closed, total TCP sockets: "..total_tcp_sockets)
				sock:close()
			end
		end
	end

	-- A complete accept function that return a client wrapper
	-- recursively (not directly in tcp_sock_wrapper() because we
	-- can't call the same function internally)
	if sock.accept then
		new_sock.accept = function(self)
			--l_o:debug("tcp.accept()")			
			-- We must accept the client first, if not, socket.select() will
			-- select it every time we don't take it, but if the number of
			-- socket is too high, we will close the socket immediately.
			local s, err = sock:accept()					
			if not s then return nil, err end		
			local accept_connection = true
			if accept_connection then 	return tcp_sock_wrapper(s)
			else return nil, err end
			
			--l_o:debug("New peer: "..s:getpeername())
			return tcp_sock_wrapper(s)
		end
	end	
	return new_sock
end


function wrap(sock)
	if string.find(tostring(socket), "#TS") then
		l_o:warn("Trying to topo-ify an already topo-socket "..tostring(socket))
		return socket
	end

	-- The Topo Socket(tm)
	local topo_sock = {}
	
	local mt = {
		-- With __index returning a function instead of a table, the inside table
		-- (sock) can't be taken from the metatable.
		--mt.__index = sock
		__index = function(table, key)
			--l_o:debug("sock."..key.."()")
			return sock[key]
		end,
		__tostring = function()
			return "#TS: "..tostring(sock) 
		end
	}

	setmetatable(topo_sock, mt)
	
	--[[
	Return some stats
	]]
	topo_sock.topo_stats = function()
		return "stats ts-socket todo";
	end
	
	topo_sock.topo_infos = function()		
		return "infos ts-socket todo"
	end
	
	topo_sock.udp = function()
		--l_o:debug("udp()")
		local sudp, err = sock.udp()
		
		if not sudp then
			return nil, err
		else
			return udp_sock_wrapper(sudp)
		end
	end
	
	topo_sock.tcp = function()
		--l_o:debug("tcp()")
		local stcp, err = sock.tcp()
		if not stcp then
			return nil, err
		else
			return tcp_sock_wrapper(stcp)
		end
	end
	
	return topo_sock
end
