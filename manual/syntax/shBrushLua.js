dp.sh.Brushes.Lua = function()
{
	var funcs	=	'_G error getfenv getmetatable ipairs loadfile' +
		' loadstring pairs pcall print rawequal' +
		' require setfenv setmetatable unpack xpcall' +
		' gcinfo loadlib LUA_PATH _LOADED _REQUIREDNAME' +
		' load module select tostring tonumber' +
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

	var splay_funcs	=	'events.run events.loop events.thread events.kill' +
		' events.periodic events.dead events.status' +
		' events.fire events.wait events.sleep events.yield' +
		' events.synchronize events.lock events.semaphore' +
		' events.stats events.infos' +
		' rpc.server urpc.server rpcq.server' +
		' rpc.stop_server urpc.stop_server rpcq.stop_server' +
		' rpc.call urpc.call rpcq.call' +
		' rpc.acall urpc.acall rpcq.acall' +
		' rpc.a_call urpc.a_call rpcq.a_call' +
		' rpc.ecall urpc.ecall rpcq.ecall' +
		' rpc.ping urpc.ping rpcq.ping' +
		' rpc.proxy urpc.proxy rpcq.proxy' +
		' net.server net.stop_server net.udp_helper net.client' +
		' log.init log.set_level log.new log.global_write' +
		' log.print log.write log.debug log.notice log.warn log.warning log.info' +
		' out.write out.file out.network' +
		' misc.dup misc.split misc.size misc.isize misc.random_pick' +
		' misc.time misc.between_c misc.hasc_ascii_to_bytes' +
		' misc.gen_string misc.table_concat misc.shuffle' +
		' misc.assert_function misc.assert_object' +
		' misc.convert_base misc.equal misc.merge misc.try misc.throw' +
		' io.init restricted_socket.init' +
		' llenc.wrap' +
		' json.wrap' +
		' utils.generate_job utils.args' +
		' benc.encode benc.decode' +
		' bits.ascii_to_bits bits.bits_to_ascii bits.show_bits' +
		' bits.is_set bits.set bits.size bits.count bits.init';

	var splay_special	=	'job.me job.me.ip job.me.port' +
		' job.nodes job.position job';

	var keywords = 'function if then else end for do loop while and or return local';

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
