log=require"splay.log"
dns=require"splay.async_dns"
dns.l_o.level=5
socket = require"socket.core"

ts = require"splay.topo_socket" --MUST BE DONE BEFORE SPLAY.BASE
ts.l_o.level=3
tb = require"splay.token_bucket"
tb.l_o.level = 3
local ts_settings={}
--modify these settings if you know what you're doing..otherwise, keep defaults
ts_settings.CHOPPING=true 
ts_settings.BW_SHARING="fair" --other possible values: 'fair'
ts_settings.MAX_BLOCK_SIZE=8192
assert(ts.init(ts_settings,job.nodes,job.topology,job.position))
socket=ts.wrap(socket)
st = require"splay.tree"
st.l_o.level =3
require"splay.base"

--REQUIRED FOR SPLAYNET: future versions of Splay won't require this code here...--
net=require"splay.net"
function handle_dcm(msg, ip, port) --the ip and port the data was sent from.
        --log:print(job.position,"RECEIVE DCM EVENT:",msg)
        local msg_tokens=misc.split(msg, " ")
        ts.handle_tree_change_event(msg_tokens)
end
dcm_udp_port=job.me.port+1 --by convention, +1 is the udp_port for topology
u = net.udp_helper(dcm_udp_port, handle_dcm)
last_proposed=nil
last_ev_broadcasted_idx=0
function dcm()
	if ts.last_event_idx>last_ev_broadcasted_idx then
		for i=last_ev_broadcasted_idx+1, ts.last_event_idx do
		  	local e=ts.tree_events[i]
		  	if e==nil then break end
		  	last_ev_broadcasted_idx = i
		  	for k,dest in pairs(job.nodes) do --should use UDP multicast,with many nodes this could be slow
		  		if not  (dest.ip == job.me.ip and dest.port ==job.me.port) then
		  		        u.s:sendto(e, dest.ip, dest.port+1)
		  		end
		  	end
		end
	end
end
--END REQUIRED FOR SPLAYNET --
rpc = require"splay.rpc"
rpc.server(job.me.port)
function call_me(position)
	log:print("I received an RPC from node "..position)
end
-- our main function
function run()
	local nodes = job.get_live_nodes() --OR the old form: job.nodes
	log:print("I'm "..job.me.ip..":"..job.me.port)
	log:print("My position in the list is: "..job.position,type(job.position))
	log:print("Live nodes:",#nodes)
	assert(ts.global_topology)
	for k,v in pairs(nodes) do
		if not (job.me.ip==v.ip and job.me.port==v.port) then
			log:print("Delay to node:",k,v.ip,v.port, ts.global_topology[v.ip..":"..v.port][1])
		end
	end	
	events.sleep(30)
	rpc.call(nodes[math.random(#nodes)], {"call_me", job.position})
	events.sleep(120)
	os.exit()
end
events.run(function()
	events.periodic(0.25, dcm) --REQUIRED TO USE SPLAYNET
	events.thread(run)
end)

