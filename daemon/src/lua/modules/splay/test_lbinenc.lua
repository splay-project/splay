local benc = require"splay.lbinenc"
assert(benc)
assert( benc.decode(benc.encode("some input"))=="some input" )
print("TEST_OK")
return true