--Benchmark json's encode/decode
misc=require"splay.misc"
json=require"json"


function test_encode(data)
	return json.encode(data)
end

-- FUNCTIONAL TESTS
-- PRIMITIVE TYPES
t1=nil --expected JSON: null
t1_enc=json.encode(t1)
print("Expected=\"nil\", got->",t1_enc)
assert(t1_enc=="null")

--t1=test_encode --expected JSON for encoded function: null (old json does not support this)
--t1_enc=json.encode(t1)
--print("Expected=\"nil\", got->",t1_enc)
--assert(t1_enc=="null")

t1="helo" --expected JSON: "helo"
t1_enc=json.encode(t1)
print("Expected=\"helo\", got->",t1_enc)
assert(t1_enc=="\"helo\"")
--
--SIMPLE ARRAYS
t1={1,2,3,4} --expected JSON: [1,2,3,4]
t1_enc=json.encode(t1)
print(t1_enc)
assert(t1_enc=="[1,2,3,4]")
--NESTED ARRAYS
t1={1,"a",{"b"}} --expected JSON: [1,"a",["b"]]
t1_enc=json.encode(t1)
print(t1_enc)
assert(t1_enc=="[1,\"a\",[\"b\"]]")

----TEST SIMPLE TABLE
t2={} --expected JSON: {"a":"b"}
t2["a"]="b"
t2_enc=json.encode(t2)
print(t2_enc)
assert(t2_enc=="{\"a\":\"b\"}","Expected {\"a\":\"b\"} but was "..t2_enc)


t2={} --expected JSON: {"a":"b","c":["d"]}
t2["a"]="b"
t2["c"]={"d"}
t2_enc=json.encode(t2)
print(t2_enc)
assert(t2_enc=="{\"a\":\"b\",\"c\":[\"d\"]}")

t3={} --expected JSON: {"a":"b","c":["d"],"n":{"e":"f"}}
t3["e"]="f"
t2["n"]=t3
t2_enc=json.encode(t2)
print(t2_enc)
assert(t2_enc=="{\"a\":\"b\",\"c\":[\"d\"],\"n\":{\"e\":\"f\"}}")

--PERFORMANCE TEST

data_sizes={1024,1024*10,1024*100,1024*1000}

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
--
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
--
print("Bench nested arrays with growing-size string")
for k,v in pairs(data_sizes) do
	print("Datasize: ",(v/1000).."K")
	local gen= misc.gen_string(v)
	for i=1,(v/100) do --to avoid stackoverlow
		gen={gen}
	end
	
	start=misc.time()
	print("Memory before:",collectgarbage( "count" ))
	enc_data=test_encode(gen)
	print("Memory after: ",collectgarbage( "count" ))
	print((v/1000).."K", misc.to_dec_string(misc.time()-start))
end
