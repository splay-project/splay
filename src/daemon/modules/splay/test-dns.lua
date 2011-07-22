require"splay.base"
--[[

Test compatibility of async_dns with LuaSocket's async_dns.

socket.dns.toip

OUTPUT SYNC_DNS
--toip--
alias:
ip:
1	77.238.178.122
2	87.248.120.148

 OUTPUT ASYNC
--toip--
header	table: 0x98d86c0
question	table: 0x98d8730
answer	table: 0x98d8a30
additional	table: 0x98d8e60
authority	table: 0x98d8cd0
answer:
1	IN A        192 yahoo.it.                    77.238.178.122
2	IN A        192 yahoo.it.                    87.248.120.148
additional:
authority:


socket.dns.tohostname

--OUTPUT SYNC_DNS
ir1.fp.vip.mud.yahoo.com
alias:
ip:
1	209.191.122.70

-- OUTPUT ASYNC_DNS
ir1.fp.vip.mud.yahoo.com.
answer:
1	IN PTR      815 70.122.191.209.in-addr.arpa. ir1.fp.vip.mud.yahoo.com.
additional:
authority:



]]		
events.run(function()
	local ip,full_ris = socket.dns.toip("yahoo.it")
	assert(ip~=nil)
	assert(full_ris~=nil)
	assert(full_ris.name=="yahoo.it", "Expected full_ris.name== yahoo.it but was "..full_ris.name)	
	assert(full_ris.ip~=nil, "Expecting field full_ris.ip")
	assert(#full_ris.ip==2, "Expecting 2 entries in full_ris.ip table")
	assert(full_ris.alias)
	print("Tests socket.dns.toip('yahoo.it') OK ")
		
	local name,full_ris = socket.dns.tohostname("209.191.122.70")
	assert(name)
	assert(full_ris)
	assert(full_ris.name==name,"Expected  full_ris.name == "..name.." but was "..full_ris["name"])
	assert(type(full_ris.ip)=="table", "Expecting field full_ris.ip")
	assert(type(full_ris.alias)=="table", "Expecting field full_ris.alias")	
	print("Tests socket.dns.tohostname('209.191.122.70') OK ")
	
	local name,full_ris = socket.dns.tohostname("127.0.0.1")
	assert(name=="localhost", 'Expected name==localhost but was'.. name)
	assert(type(full_ris.ip)=="table", "Expecting field full_ris.ip to be a table")
	assert(type(full_ris.alias)=="table", "Expecting field full_ris.alias to be a table")	
	
	local name,full_ris = socket.dns.tohostname("10.0.2.1")
	assert(name==nil)
	assert(full_ris=="host not found")
	print("Tests socket.dns.tohostname('10.0.2.1') OK ")
end)
