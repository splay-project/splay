require"splay.base"

function SPLAYschool()
	local nodes = job.get_live_nodes()
	log:print("I'm "..job.me.ip..":"..job.me.port)
	log:print("My position in the list is: "..job.position)
	--os.exit()
end
--events.thread(SPLAYschool)
events.loop(function()
	local ave_spent_time = 0
	local nb_tests = 100
	for i=1,nb_tests do
		--print("Test n. "..i)
		local init_time = misc.time()
		--print("INIT="..init_time)
		local a = nil
		local b = nil
		for j=1,833000 do
			a = math.pow(1345+math.pow(j,1345),17)
			b = math.cos(a+(1/j))
		end
		local end_time = misc.time()
		--print("END="..end_time)
		ave_spent_time = ave_spent_time + (end_time - init_time)/nb_tests
		--print("finished calculating, sleep for 0.5sec")
	end
	log:print("Average spent time="..ave_spent_time.." seconds")
end)