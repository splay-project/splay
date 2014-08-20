require"splay.base"
local lxyssl=require"lxyssl" ---SUBMIT THIS LIB FIRST!
local assert=assert

function encrypt(key, data)
	assert(key  ~= nil, "Empty key.")
	assert(#key == 32,"Lenght of key must be ==32 chars (AES256)")
	assert(data ~= nil, "Empty data.")	 
	local iv=lxyssl.hash('md5'):digest(key)
	local e =lxyssl.aes(key,256):cfb_encrypt(data,iv)
	return e
end

--[[
-- Decrypts string data with password password.
-- key  - the decryption key is generated from this string
-- data      - string to encrypt
]]--
function  decrypt(key, data)
	assert(key  ~= nil, "Empty key.")
	assert(#key ==32,"Lenght of key must be ==32 chars (AES256)")
	assert(data ~= nil, "Empty data.")
	
    local iv=lxyssl.hash('md5'):digest(key)
    local d = lxyssl.aes(key,256):cfb_decrypt(data,iv)  
    return d
end

--[[[
Generate a random password of size len. The default size is 32, required
to use AES-256 cipher.
]]--
function random_pwd(len)
	local l=32
	if len ~= nil then l=len end
	return lxyssl.rand(l)
end

local function example()
	key=lxyssl.rand(32)
	plaintext=('a'):rep(1000)
	e=encrypt(key,plaintext)
	d=decrypt(key,e)
	assert(decrypt(key,encrypt(key,plaintext))==plaintext)
end
events.run(function() 
	log:print("Start AES example")
	example() 
	log:print("End AES example")
end)
