require"splay.base"
local rpc = require"splay.rpc"
paxos = require"splay.paxos"

local node_n = tonumber(arg[1])
local total_nodes = tonumber(arg[2])
local max_retries = 5
local rpc_port = 30000+node_n

print("im node="..node_n..", using port="..rpc_port)

rpc.server(rpc_port)

local peers = {}

if job then
	peers = job.nodes()
else
	for i=1,total_nodes do
		table.insert(peers, {ip="127.0.0.1", port=30000+i})
	end
end

events.run(function()
	if node_n == 2 then
		events.sleep(3)
		paxos.paxos_write(1, peers, max_retries, "hello")
		events.sleep(3)
		paxos.paxos_write(2, peers, max_retries, 6)
		events.sleep(3)
		paxos.paxos_write(1, peers, max_retries, "HI THERE")
		events.sleep(3)
		--paxos.paxos_write(4, peers, max_retries, 10)
	elseif node_n == 5 then
		events.sleep(20)
		--paxos.paxos_read(10, peers, max_retries)
	end
end)