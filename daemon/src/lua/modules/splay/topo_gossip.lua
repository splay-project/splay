local net=require"splay.net"
local pairs=pairs
local print=print
local table=table
local ts=require"splay.topo_socket"
local log = require"splay.log"
local misc= require"splay.misc"
module("splay.topo_gossip")
--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

nodes=nil
me=nil
gossip_udp_port=nil
u=nil
last_proposed=nil

function same_peer(a,b)
	return a.ip == b.ip and a.port == b.port
end
function handle_gossip(msg, ip, port) 
	local msg_tokens=misc.split(msg, " ")	
	local e_t={} 
	for i=2,#msg_tokens do table.insert(e_t,msg_tokens[i]) end
	local rec_e=table.concat(e_t," ")
	if msg_tokens[1]==">" then  -- '>' for active thread, '<' for passive
		log:debug("[handle-active-gossip]",rec_e) --, ip, port
		--local my_e=ts.tree_events[ts.last_event_idx]
		--if my_e~=nil then
		--	local risp="< "..my_e	
		--	u.s:sendto(risp, ip, port)
		--end
		ts.handle_tree_change_event(e_t)
	else		
		log:debug("[handle-passive-gossip]",rec_e) --, ip, port 
		ts.handle_tree_change_event(e_t) 		
	end
end
function gossip()
	local e=ts.tree_events[ts.last_event_idx]
	if e==nil or e==last_proposed then return end --infect-and-die
	last_proposed=e	
	for k,dest in pairs(nodes) do --FULL-KNOWLEDGE
		if not same_peer(dest, me) then
			local msg="> "..e
			l_o:debug(msg)
			u.s:sendto(msg, dest.ip, dest.port+1)
		end
	end
end
function init(job)
	nodes=job.nodes
	me=job.me
	gossip_udp_port=job.me.port+1
	u = net.udp_helper(gossip_udp_port, handle_gossip)
end