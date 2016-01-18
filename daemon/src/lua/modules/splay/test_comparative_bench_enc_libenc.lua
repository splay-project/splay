local misc=require"splay.misc"
local benc=require"splay.benc"
local lbinenc=require"splay.lbinenc"

data_sizes={
	1024,           --1Kb
	1024*10,  		--10Kb
	1024*100,		--100Kb	
	1024*1024,	    --1Mb
	1024*1024*10,   --10Mb
	1024*1024*100,  --100Mb
	1024*1024*1024} --1Gb 

function test_encode(encoder,data)
	return encoder.encode(data)
end

for k,v in pairs(data_sizes) do
	local c={misc.gen_string(v)}	
	local t=misc.time()
	local benc_enc_data=test_encode(benc,c)
	print(v,"benc.encoded in:",misc.time()-t)
	local t=misc.time()
	local lbinenc_enc_data=test_encode(lbinenc,c)
	print(v,"lbinenc.encoded in:",misc.time()-t)
end
print("TEST_OK")
return true
