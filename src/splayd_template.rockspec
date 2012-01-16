package = "splayd"
version = "##VERSION##"
source = {
	url="http://www.splay-project.org/splay/release/splayd_##VERSION_URL##.tar.gz"
}
description = {
   summary = "SPLAY Deamon and Libraries.",
   detailed = [[
     SPLAY simplifies the prototyping and development of large-scale distributed applications and overlay networks. SPLAY covers the complete chain of distributed system design, development and testing: from coding and local runs to controlled deployment, experiment control and monitoring.
	SPLAY allows developers to specify their distributed applications in a concise way using a specialized language based on Lua, a highly-efficient embeddable scripting language. SPLAY applications execute in a safe environment with restricted access to local resources (file system, network, memory) and can be instantiated on a large variety of testbeds composed a large set of nodes with a single command.
	SPLAY is the outcome of research and development activities at the Computer Science Department of the University of Neuchatel.
   ]],
   homepage = "http://www.splay-project.org",
   license = "GPLv3"
}
dependencies = {
   "lua >= 5.1",
   "luasec >= 0.4-3",
   "luacrypto >= 0.2.0",
   "luasocket >= 2.0.2",
}
supported_platforms= { "macosx", 
                       "linux", 
                       "freebsd"
}
build = {
  type = "make",
  install_target= "all",
  install ={
  	lib={
		"splay_core.so",
		["splay.misc_core"]="misc_core.so",
		["splay.data_bits_core"]="data_bits_core.so",
		"luacrypto/crypto.so"
	},
	lua={
		"modules/json.lua",
		"modules/splay.lua",
		["splay.async_dns"]="modules/splay/async_dns.lua",
		["splay.base"]="modules/splay/base.lua",
		["splay.benc"]="modules/splay/benc.lua",
		["splay.bits"]="modules/splay/bits.lua",
		["splay.coxpcall"]="modules/splay/coxpcall.lua",
		["splay.databits"]="modules/splay/data_bits.lua",
		["splay.events"]="modules/splay/events.lua",
		["splay.events_new"]="modules/splay/events_new.lua",
		["splay.json"]="modules/splay/json.lua",	
		["splay.llenc"]="modules/splay/llenc.lua",
		["splay.log"]="modules/splay/log.lua",
		["splay.luasocket"]="modules/splay/luasocket.lua",
		["splay.misc"]="modules/splay/misc.lua",	
		["splay.net"]="modules/splay/net.lua",	
		["splay.out"]="modules/splay/out.lua",	
		["splay.queue"]="modules/splay/queue.lua",	
		["splay.restricted_io"]="modules/splay/restricted_io.lua",	
		["splay.restricted_socket"]="modules/splay/restricted_socket.lua",
		["splay.rpc"]="modules/splay/rpc.lua",	
		["splay.rpcq"]="modules/splay/rpcq.lua",	
		["splay.sandbox"]="modules/splay/sandbox.lua",	
		["splay.socket"]="modules/splay/socket.lua",	
		["splay.socket_events"]="modules/splay/socket_events.lua",	
		["splay.urpc"]="modules/splay/urpc.lua",	
		["splay.utils"]="modules/splay/utils.lua",	
	},
	--[[
	bin = {
        "splayd",
		"splayd.lua",
        "settings.lua",
		"jobd",
		"jobd.lua",
		"cert.pem",
		"client.pem",
		"key.pem",
		"req.pem",
		"rootkey.pem",
		"root.pem",
		"rootreq.pem"
      },
	]]
  }  
}	
