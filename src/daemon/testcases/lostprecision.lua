require("splay.base")
rpc = require("splay.rpc")

rpc.server(job.me.port)

function print_num(num)
    print("Server received the following number: "..num)
    print("Which is properly formatted as: "..string.format("%.0f", num))
    return num
end

events.run(function()
	print("MY POSITION:", job.position,type(job.position) )
	if tonumber(job.position)==1 then		
		print("Waiting for rpc...")
		events.sleep(4)
		events.exit()
	else 	
		events.sleep(2)			
		--local smallnum = 12345
		--print("SMALLNUM - Client is sending: "..smallnum)
		--print("SMALLNUM - Which is properly formatted as: "..string.format("%.0f",smallnum))
		--local ret = rpc.call(job.get_live_nodes()[1], {"print_num",smallnum})
		--print("SMALLNUM - Client received back: "..ret)
		--print("SMALLNUM - Which is properly formatted as: "..string.format("%.0f",ret))
		
		local bignum = math.pow(2,52) - 1 --lua can accurately store integers up to 2^52 - 1
		print("BIGNUM - Client is sending: "..bignum)
		print("BIGNUM - Which is properly formatted as: "..string.format("%.0f",bignum))
		local ret = rpc.call(job.get_live_nodes()[1], {"print_num",bignum})
		print("BIGNUM - Client received back: "..ret)
		print("BIGNUM - Which is properly formatted as: "..string.format("%.0f",ret))
		events.exit()
	end
end)
