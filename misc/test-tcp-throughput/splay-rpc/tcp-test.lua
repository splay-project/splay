require"splay.base"
rpc = require"splay.rpc"

function recv_data(data)
	return "OK"
end

--starts the server
rpc.server(job.me.port)

events.run(function()
	--if node 1 (server)
	if job.position == 1 then
		log:print("Server on IP="..job.me.ip..", port="..job.me.port)
	--if not (client)
	else
		events.sleep(10)
		local job_nodes = job.nodes()
		local server_addr = job_nodes[1]
		local size = 1048576
		local n_times = 10000
		local payload = string.rep("a", size)
		while size > 2000 do
			local time1 = 0
			--repeat n_times
			for i = 1, n_times do
				--registers the starting time in seconds (with .4 digit precision)
				time0 = misc.time()
				--makees the rpc call
				rpc.call(server_addr, {"recv_data", payload})
				--registers 2nd timestamp
				time1 = time1 + misc.time() - time0
				if i % 100 == 0 then
					log:print("Size "..size.." "..i.."th test")
				end
			end
			time1 = time1/n_times
			log:print("Size = "..size..", Time 1 = "..time1)
			size = size / 2
			payload = string.rep("a", size)
		end
	end
end)
