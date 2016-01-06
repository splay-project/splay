log = require"splay.log"
assert(log.global_filter) --	function: 0x7faec94060b0
assert(log.global_out) --	function: 0x7faec940eb20
assert(log.global_write) --	function: 0x7faec940e910
assert(log.global_level) --	3
assert(log.new) --	function: 0x7faec940e620

local l_o = log.new(5, "[inf-logger]")
--assert(log._DESCRIPTION=="Splay Log")
--assert(log._COPYRIGHT==	"Copyright 2006 - 2011")
--assert(log._VERSION ==	1)
--assert(log.filter)
assert(l_o.i) --	function: 0x7faec940be20
assert(l_o.debug) --	function: 0x7faec940e330
assert(l_o.n) --	function: 0x7faec940be20
assert(l_o.p) --	function: 0x7faec940b5e0
assert(l_o.error) --	function: 0x7faec940c750
assert(l_o.warn) --	function: 0x7faec940c6e0
assert(l_o.w) --	function: 0x7faec940c6e0
assert(l_o.info) --	function: 0x7faec940be20
assert(l_o.d) --	function: 0x7faec940e330
assert(l_o.print) --	function: 0x7faec940b5e0
assert(l_o.e) --	function: 0x7faec940c750
assert(l_o.warning) --	function: 0x7faec940c6e0
assert(l_o.notice) --	function: 0x7faec940be20
assert(l_o:print("print-level","test"))

local l_o = log.new(1, "[deb-logger]")
assert(l_o:debug("test"))

a_module = {
	l_o = log.new(1, "[a_module]")
}
assert(a_module.l_o:print("test"))