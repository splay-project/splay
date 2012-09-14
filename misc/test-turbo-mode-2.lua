require"splay.base"
misc = require"splay.misc"
rpc = require"splay.rpc"

function rec_ping()
	return true
end

function SPLAYschool()
	local nodes = job.get_live_nodes()
	--log:print("I'm "..job.me.ip..":"..job.me.port)
	--log:print("My position in the list is: "..job.position)
	--os.exit()
end
--events.thread(SPLAYschool)
events.loop(function()

	local ave_time_spent = 0
	local stdev_time_spent = 0
	local nb_tests = 100
	local nodes = job.get_live_nodes()

	if job.position = 1 then
		for i=1,nb_tests do
			--print("Test n. "..i)
			local init_time = misc.time()
			--print("INIT="..init_time)
			local unsorted_nodes = misc.random_pick(nodes, #nodes)

			local answer = nil

			for k,v in ipairs(unsorted_nodes) do
				answer = rpc.acall(v, {"rec_ping"})
			end

			local end_time = misc.time()
			--print("END="..end_time)
			ave_time_spent = ave_time_spent + (end_time - init_time)
			stdev_time_spent = stdev_time_spent + math.pow((end_time - init_time), 2)
			--print("finished calculating, sleep for 0.5sec")
		end
		ave_time_spent = ave_time_spent/nb_tests
		stdev_time_spent = math.sqrt((stdev_time_spent/nb_tests - math.pow(ave_time_spent, 2)))
		log:print("Time spent, average="..ave_time_spent..", standard dev="..stdev_time_spent)
	end
end)