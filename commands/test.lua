#!/blabla/lua this line must be auto-removed

--[[
BEGIN SPLAY RESSOURCES RESERVATION

nb_splayds 3
bits 32

END SPLAY RESSOURCES RESERVATION
--]]
--list_size 1

--for i, j in pairs(_G) do print(i, j) end

require"splay.base"

-- (for RPC)
function concatenate(a, b)
	return a..b
end

events.loop(function()
	local my_err = false

	print(">> Splay test script")
	print()

	collectgarbage()
	collectgarbage()
	print("Memory: "..gcinfo().." ko")
	print(_VERSION)
	if _SPLAYD_VERSION then
		print("Splayd v.".._SPLAYD_VERSION)
	else
		my_err = true
		print("ERROR: no splayd version")
	end
	print()

	print("> Test 0: packages")
	if package then
		if package.loaders then
			my_err = true
			print("ERROR: package loaders still exists.")
		end
		if package.path or package.cpath then
			my_err = true
			print("ERROR: path exists.")
		end
		if package.loadlib then
			my_err = true
			print("ERROR: loadlib exists.")
		end
	end
	print()

	print("> Test 1: strings")
	print("Visual test to see if json encoded file transfer has not corrupted the file.)")
	print("\\ line one \nline two \na pseudo json utf-16 char: \\u4141")
	--[[ Correct output:
	\ line one 
	line two 
	a pseudo json utf-16 char: \u4141
	--]]
	print()

	print("> Test 2: Global vars that must NOT exists")
	if not so and not pid and not err and not err_code and not msg
			and not ori_print and not splayd and not jobs_log and not log_file
			and not debug and not _G.hello then
		print("OK: no global vars")
	else
		my_err = true
		print("ERROR:", so, pid, err, err_code, msg, ori_print,
				splayd, jobs_log, log_file, debug)
	end
	print()

	print("> Test 3: Script arguments:")
	if arg then
		i = 0
		while arg[i] do
			print(i..": "..arg[i])
			i = i + 1
		end
	else
		print("No command line arguments, maybe we are bytecode Lua.")
	end
	print()

	print("> Test 4: Restricted sockets")
	print(socket)
	if not socket.infos then
		my_err = true
		print("ERROR: Not a restricted socket.")
	else
		print(socket.infos())
	end
	print()

	-- on local test (controller + splayd on the same computer),
	-- this should be OK
	--print(socket.connect("127.0.0.1", 10000))

	print("> Test 5: job list:")
	if job then
		print("OK: my position is: "..job.position)
		print("> me: "..job.me.ip..":"..job.me.port)
		print("> list type: "..job.list_type.." (size: "..#job.nodes..")")
		print("> All jobs list:")
		for pos, sl in pairs(job.nodes) do
			print("", pos.." ip: "..sl.ip..":"..sl.port)
		end
	else
		my_err = true
		print "ERROR: No job list."
	end
	print()

	print("> Test 6: Restricted IO:")
	if not io.infos then
		my_err = true
		print("ERROR: no restricted IO.")
	else
		print("OK: restricted IO.")
		io.infos()
	end
	if io.init({}) then
		my_err = true
		print("ERROR: restricted IO not initialized.")
	else
		print("OK: restricted IO initialized.")
	end
	print()

	print("> Test 7: Misc:")
	if misc.time then
		print(misc.time(), os.time())
		print("OK: misc loaded.")
	else
		my_err = true
		print("ERROR: misc not loaded.")
	end
	print()

	print("> Test 8: RPCs:")
	rpc = require("splay.urpc")
	rpc.server(job.me)
	local ok, r = rpc.a_call(job.me, {"concatenate", "one ", "two"})
	if ok and r[1] == "one two" then
		print("OK: RPC.")
	else
		my_err = true
		print("ERROR: RPC.")
	end
	print()

	print("> Test 9: Mem:")
	collectgarbage()
	collectgarbage()
	local m1 = gcinfo()
	print("Memory: "..gcinfo().." ko")
	local a = "a"
	for i = 1, 14 do -- 16 ko
		a = a..a
	end
	collectgarbage()
	collectgarbage()
	local m2 = gcinfo()
	local mt = m1 + (string.len(a) / 1024)
	if m2 >= mt and m2 <= mt + 1 then
		print("OK: memory allocation count.")
	else
		my_err = true
		print("ERROR: memory allocation count.")
	end
	a = nil
	collectgarbage()
	collectgarbage()
	if gcinfo() == m1 or gcinfo() == m1 + 1 then
		print("OK: memory deallocation.")
	else
		my_err = true
		print("ERROR: memory deallocation.")
	end
	print()

	print("> Test 10: Log:")
	log = require("splay.log")
	out = require("splay.out")
	log.global_out = out.print()
	log:warning("Testing log with out")
	print()

	print("------------------------------------------------------")
	if not my_err then
		print("CHECKS OK, the application is executed in a secure environment.")
	else
		print("CHECKS PROBLEM, verify the sandbox and initialization.")
	end
	print("------------------------------------------------------")
	print()
	collectgarbage()
	collectgarbage()
	print("Memory: "..gcinfo().." ko")

	---- additionnal functions

	if arg then
		if arg[1] == "disk" then
			-- TODO
		end
		if arg[1] == "mem" then
			local s = "."
			while string.len(s) < 10000000 do
				s = s..s
			end
		end
		if arg[1] == "code" then
			print(job.code)
		end

		if arg[1] == "perm" then
			while true do
				print(os.time())
				socket.sleep(200)
			end
		end
	end

	events.sleep(1)
	os.exit()
end)
