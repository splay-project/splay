-- Run with:
-- lua install_check.lua
print("------------- start testing installation -------------")

-- Lua
require"table"
require"math"
require"os"
require"io"
require"string"

-- Splay
require"splay"
require"splay.base"
require"splay.data_bits"
require"splay.misc"
require"splay.net"
require"splay.rpc"
require"splay.urpc"

-- JSON4Lua
require"json"

if json and not json.leo then
	print("!!! bad json version, you need the modified one (in modules/json.lua")
end

-- LuaSocket other libraries
require"socket.ftp"
require"socket.http"
require"socket.smtp"
require"socket.tp"
require"socket.url"
require"mime"
require"ltn12"

-- LuaSec
require"ssl"

-- Luacrypto
require"crypto"

print("------------- end testing installation -------------")
print()
print("If there is no error messages, all the required libraries are ")
print("installed and found on this system.")
