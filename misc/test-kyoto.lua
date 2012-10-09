local kc = require"kyotocabinet"
local show_mem_disk = "kyotomem=$(ps aux | grep test.kyoto | grep -v grep | sed s/'  *'/' '/g | cut -f6 -d' ');kyotodisk=$(ls -l | grep test1.kch | sed s/'  *'/' '/g | cut -f5 -d' ');echo \"mem=$kyotomem disk(B)=$kyotodisk disk(kB)=$(expr $kyotodisk / 1024)\""

print("before all")
os.execute(show_mem_disk)

local db = kc.DB:new()

db:open("test1.kch")

print("after open")
os.execute(show_mem_disk)

db:clear()

print("after clear")
os.execute(show_mem_disk)

local tbl1 = {}

for j=1,4096*8 do
	table.insert(tbl1, string.char(math.random(250)))
end

print("after tbl1")
os.execute(show_mem_disk)

local str1 = table.concat(tbl1)

print("after str1")
os.execute(show_mem_disk)

tbl1 = nil

print("after tbl1 = nil")
os.execute(show_mem_disk)

collectgarbage()

print("after collectgarbage, before iterations")
os.execute(show_mem_disk)

for i=1,20 do
	for k=1,400 do
		db:set(i.."x"..k, str1)
	end
	--db:synchronize(true, nil)
	--collectgarbage()
	io.write("db_count="..db:count().." db_size="..db:size().." ")
	io.flush()
	os.execute(show_mem_disk)
end

db:close()
print("after closing DB:")
os.execute(show_mem_disk)