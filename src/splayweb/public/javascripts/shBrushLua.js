dp.sh.Brushes.Lua = function()
{
	var funcs	=	'_G getfenv getmetatable ipairs loadfile' +
		' loadstring pairs pcall print rawequal' +
		' require setfenv setmetatable unpack xpcall' +
		' gcinfo loadlib LUA_PATH _LOADED _REQUIREDNAME' +
		' load module select' +
		' package.cpath' +
		' package.loaded' +
		' package.loadlib' +
		' package.path' +
		' package.preload' +
		' package.seeall' +
		' coroutine.running' +
		' coroutine.create' +
		' coroutine.resume' +
		' coroutine.status' +
		' coroutine.wrap' +
		' coroutine.yield' +
		' string.byte' +
		' string.char' +
		' string.dump' +
		' string.find' +
		' string.len' +
		' string.lower' +
		' string.rep' +
		' string.sub' +
		' string.upper' +
		' string.format' +
		' string.gsub' +
		' string.gfind' +
		' table.getn' +
		' table.setn' +
		' table.foreach' +
		' table.foreachi' +
		' string.gmatch' +
		' string.match' +
		' string.reverse' +
		' table.maxn' +
		' table.concat' +
		' table.sort' +
		' table.insert' +
		' table.remove' +
		' math.abs' +
		' math.acos' +
		' math.asin' +
		' math.atan' +
		' math.atan2' +
		' math.ceil' +
		' math.sin' +
		' math.cos' +
		' math.tan' +
		' math.deg' +
		' math.exp' +
		' math.floor' +
		' math.log' +
		' math.log10' +
		' math.max' +
		' math.min' +
		' math.mod' +
		' math.fmod' +
		' math.modf' +
		' math.cosh' +
		' math.sinh' +
		' math.tanh' +
		' math.pow' +
		' math.rad' +
		' math.sqrt' +
		' math.frexp' +
		' math.ldexp' +
		' math.random' +
		' math.randomseed' +
		' math.pi' +
		' io.stdin' +
		' io.stdout' +
		' io.stderr' +
		' io.close' +
		' io.flush' +
		' io.input' +
		' io.lines' +
		' io.open' +
		' io.output' +
		' io.popen' +
		' io.read' +
		' io.tmpfile' +
		' io.type' +
		' io.write' +
		' os.clock' +
		' os.date' +
		' os.difftime' +
		' os.execute' +
		' os.exit' +
		' os.getenv' +
		' os.remove' +
		' os.rename' +
		' os.setlocale' +
		' os.time' +
		' os.tmpname' +
		' debug.debug' +
		' debug.gethook' +
		' debug.getinfo' +
		' debug.getlocal' +
		' debug.getupvalue' +
		' debug.setlocal' +
		' debug.setupvalue' +
		' debug.sethook' +
		' debug.traceback' +
		' debug.getfenv' +
		' debug.getmetatable' +
		' debug.getregistry' +
		' debug.setfenv' +
		' debug.setmetatable';

	var splay_funcs	=	'events.loop events.thread events.periodic events.dead' +
		' events.fire events.wait events.sleep events.yield events.synchronize' +
		' events.lock events.semaphore events.stats' +
		' rpc.server rpc.call rpc.a_call rpc.ping rpc.proxy' +
		' urpc.server urpc.call urpc.a_call urpc.ping urpc.proxy' +
		' net.server net.udp_helper' +
		' log.init log.set_level log.write log.debug log.notice log.warn' +
		' log.error log.print' +
		' misc.dup misc.split misc.size misc.isize misc.random_pick misc.random_pick_one' +
		' misc.time misc.between_c misc.hasc_ascii_to_bytes' +
		' misc.gen_string misc.table_concat' +
		' io.init restricted_socket.init' +
		' llenc.wrap' +
		' json.wrap' +
		' benc.encode benc.decode' +
		' bits.ascii_to_bits bits.bits_to_ascii bits.show_bits bits.is_set bits.set';

	var splay_special	=	'job.me job.nodes job.position job';

	var keywords = 'function if then else end for do loop while and or';

		//{regex: new RegExp('/\\*[\\s\\S]*?\\*/', 'gm'), css: 'comment'},
		//{regex: new RegExp('--\\[\\[.*\\]\\]', 'gm'), css: 'comment'},
		//{regex: new RegExp('\\$\\w+', 'g'), css: 'vars'},
	this.regexList = [
		{regex: new RegExp('--.*$', 'gm'),	css: 'comment'},
		{regex: dp.sh.RegexLib.DoubleQuotedString, css: 'string'},
		{regex: dp.sh.RegexLib.SingleQuotedString, css: 'string'},
		{regex: new RegExp(this.GetKeywords(funcs), 'gm'), css: 'func'},
		{regex: new RegExp(this.GetKeywords(splay_funcs), 'gm'), css: 'splay_func'},
		{regex: new RegExp(this.GetKeywords(splay_special), 'gm'), css: 'splay_special'},
		{regex: new RegExp(this.GetKeywords(keywords), 'gm'), css: 'keyword'}
		];

	this.CssClass = 'dp-c';
}

dp.sh.Brushes.Lua.prototype	= new dp.sh.Highlighter();
dp.sh.Brushes.Lua.Aliases	= ['lua'];
