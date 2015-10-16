local benc = require"splay.benc"
assert(benc)
assert( benc.decode(benc.encode("some input"))=="some input" )
print("TEST_OK")
return true
