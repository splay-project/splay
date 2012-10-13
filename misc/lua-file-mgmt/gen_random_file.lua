local function gen_rand_byte()
	return string.char(math.random(256)-1)
end

local function gen_rand_non0_byte()
	return string.char(math.random(255))
end

local txt_tbl = {" ", " ", " ", "\n"}
for i=48,57 do
	table.insert(txt_tbl, string.char(i))
	table.insert(txt_tbl, string.char(i))
end
for i=65,90 do
	table.insert(txt_tbl, string.char(i))
	table.insert(txt_tbl, string.char(i))
	table.insert(txt_tbl, string.char(i+32))
	table.insert(txt_tbl, string.char(i+32))
end
local function gen_rand_txt_byte()
	return txt_tbl[math.random(#txt_tbl)]
end

local gen_byte = {
	["rand"] = gen_rand_byte,
	["rand_non_zero"] = gen_rand_non0_byte,
	["rand_text"] = gen_rand_txt_byte
}
local multipliers = {["B"]=true, ["kB"]=1, ["MB"]=1024}

if (not gen_byte[arg[1]]) or (not multipliers[arg[3]]) or not tonumber(arg[2]) then
	print()
	print ("Syntax: lua gen_random_file.lua [random_mode] size [multiplier]")
	print()
	print ("\trandom_modes: \"rand\", \"rand_text\", \"rand_non_zero\"")
	print ("\tmultipliers: \"B\", \"kB\" (1024 B), \"MB\" (1024 kB)")
	print()
	print ("Example: lua gen_random_file.lua rand_non_zero 1 kB")
	print()
	os.exit()
end

math.randomseed(os.time())

local f1 = io.open(arg[1].."_"..arg[2]..arg[3]..".not_txt", "w")

local add_byte = gen_byte[arg[1]]

local byte_tbl = {}
local function add_kbyte()
	for i=1,1024 do
		byte_tbl[i] = add_byte()
	end
	return table.concat(byte_tbl)
end

if arg[3] == "B" then
	for i=1,tonumber(arg[2]) do
			f1:write(add_byte())
	end
else
	for i=1,tonumber(arg[2])*multipliers[arg[3]] do
			f1:write(add_kbyte())
	end
end

f1:close()