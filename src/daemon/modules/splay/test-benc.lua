--Benchmark benc's encode/decode
misc=require"splay.misc"
benc=require"splay.benc"


function test_encode(data)
	return benc.encode(data)
end

data_sizes={1000,10000,100000,1000000}

--print("Bench encode numbers")
--for k,v in pairs(data_sizes) do
--	local gen=tonumber(misc.gen_string(v))
--	start=misc.time()
--	enc_data=test_encode(gen)
--	print(v, misc.time()-start)
--end
--
--print("Bench encode strings")
--for k,v in pairs(data_sizes) do
--	local gen=misc.gen_string(v)
--	start=misc.time()
--	enc_data=test_encode(gen)
--	print(v, misc.time()-start)
--end
--
--print("Bench array with numbes")
--for k,v in pairs(data_sizes) do
--	local gen={tonumber(misc.gen_string(v))}
--	start=misc.time()
--	enc_data=test_encode(gen)
--	print(v, misc.time()-start)
--end
--
--
--print("Bench array with strings")
--for k,v in pairs(data_sizes) do
--	local gen={misc.gen_string(v)}
--	start=misc.time()
--	enc_data=test_encode(gen)
--	print(v, misc.time()-start)
--end

--print("Bench nested arrays with fixed-size string")
--for k,v in pairs(data_sizes) do
--	
--	local gen="a"
--	for i=1,(v/100) do --to avoid stackoverlow
--		gen={gen}
--	end
--	
--	start=misc.time()
--	enc_data=test_encode(gen)
--	print((v/100), misc.time()-start)
--end

print("Bench nested arrays with growing-size string")
for k,v in pairs(data_sizes) do
	
	local gen= misc.gen_string(v)
	for i=1,(v/100) do --to avoid stackoverlow
		gen={gen}
	end
	
	start=misc.time()
	enc_data=test_encode(gen)
	print((v/1000).."K", misc.to_dec_string(misc.time()-start))
end

