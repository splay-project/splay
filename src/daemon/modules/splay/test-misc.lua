--Unit tests for functions in splay.misc 
misc=require"splay.misc"
function test_bitcalc_10bytes()
	local ris=misc.bitcalc(10)
	assert(ris.bytes==10)
	assert(ris.kilobytes==ris.bytes/1024,'Expected 0 but was '..ris.kilobytes)
end

function test_bitcalc_10kb()
	local ris=misc.bitcalc(10*1024)
	assert(ris.bytes==10*1024, "Expected 10 but was "..ris.bytes)
	assert(ris.kilobytes==ris.bytes/1024,'Expected '..(ris.bytes/1024)..' but was '..ris.kilobytes)
	assert(ris.megabytes==ris.kilobytes/1024,'Expected '..(ris.kilobytes/1024)..' but was '..ris.megabytes)
end

function test_bitcalc_10Mb()
	local ris=misc.bitcalc(10*1024*1024)
	assert(ris.bytes==10*1024*1024, "expected "..(10*1024*1024).." but was "..ris.bytes)
	assert(ris.kilobytes==ris.bytes/1024,'Expected '..(ris.bytes/1024)..' but was '..ris.kilobytes)
	assert(ris.megabytes==ris.kilobytes/1024,'Expected '..(ris.kilobytes/1024)..' but was '..ris.megabytes)
end

function test_bitcalc_a()
	local ris=misc.bitcalc(257075) --a value
	
	assert(ris.bits==2056600, "Expected 2056600 but was "..ris.bits)
	assert(ris.bytes==257075, "Expected 257075 but was "..ris.bytes)
	
	assert(ris.kilobits==2008.3984375, "Expected 2008.3984375 but was "..ris.kilobits)
	assert(ris.kilobytes==251.0498046875,'Expected 251.0498046875 but was '..ris.kilobytes)
	
	assert(math.abs(ris.megabytes-0.245165824890137)<0.000000001,'Expected 0.245165824890137 but was '..ris.megabytes)
	assert(math.abs(ris.megabits-1.96132659912109)<0.000000001,'Expected 1.96132659912109 but was '..ris.megabits)
	
	assert(math.abs(ris.gigabytes-0.000239419750869274)<0.000000001,'Expected 0.000239419750869274 but was '..ris.gigabytes)
	assert(math.abs(ris.gigabits-0.00191535800695419)<0.000000001,'Expected 0.00191535800695419 but was '..ris.gigabits)
	
	
	assert(math.abs(ris.terabytes-2.33808350458276e-07)<0.000000001,'Expected 0.000239419750869274 but was '..ris.terabytes)
	assert(math.abs(ris.petabytes-2.2832846724441e-10)<0.000000001,'Expected 2.2832846724441e-10 but was '..ris.petabytes)
end

function test_bitcalc_b()
	local ris=misc.bitcalc(1024*1024*1024*1024) --a value
	
	print("bits:",ris.bits )
	print("bytes:",ris.bytes)
	print("kb:",ris.kilobits)
	print("KB:",ris.kilobytes)
	print("MB:",ris.megabytes)
	print("Mb:",ris.megabits)
end

function test_to_dec_string()
	local bignum =  math.pow(2,52) - 1
	local bignum_tos = string.format("%.0f",bignum)
	assert(bignum_tos=="4503599627370495", 'Expected 4503599627370495 but was'..bignum_tos )
	
	local bignum_to_dec_string = misc.to_dec_string(bignum)
	assert(bignum_to_dec_string=="4503599627370495", "Expected 4503599627370495 but was "..bignum_to_dec_string)
end

function test_time()
	assert(misc.time)
	local t= misc.time()
	assert(t)
	assert(misc.ctime)		
end
test_bitcalc_10bytes()
test_bitcalc_10kb()
test_bitcalc_10Mb()
test_bitcalc_a()
test_bitcalc_b()
test_to_dec_string()
test_time()