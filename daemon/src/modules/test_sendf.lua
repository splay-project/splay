FILE_SIZE=1024*1024
require"splay.base"
local net = require"splay.net"
local sendf=require"splay.sendf"
local socket=require"splay.socket"
function echo_server(s)
  while true do
    local r = s:receive("*l")
	print(r)
  end
end
net.server(20000, echo_server)
events.run(function()
	--create a connection to write the file into	
	local s,err = socket.tcp()
	local ok,msg = s:connect("127.0.0.1",20000) --connect to the echo-server	
	assert(ok)
	assert(s:getfd()," cannot get FD from socket ")
	--write tmp file
	local tmpfile = io.tmpfile() 
	tmpfile:write(string.rep("a",FILE_SIZE))
	tmpfile:write("\n")
	tmpfile:flush()
	--read its size now
	local file_size,err = tmpfile:seek("end")
	for i=1,100 do
		sendf.copy_file_to_socket(tmpfile, s:getfd(), file_size, function() end)
	end
	print("copy_file_to_socket finished")
	tmpfile:close()
	events.exit()
end)

