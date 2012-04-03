require"splay.base"
require"chunk2"
local events=require"splay.events"
events.run(function()
	events.periodic(1,chunky())
	events.periodic(1,function() print("chunk1") end)
end)
