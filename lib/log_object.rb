# Wrapper to add function call logs on an object
class LogObject
	def initialize(o, name = "UN", level = Logger::DEBUG)
		@o = o
		@name = name
		@level = level
	end

	def method_missing methodname, *args, &block
		if $log
			$log.add(@level, "#{@name}: #{methodname}(#{args})")
		end
		return @o.send(methodname, *args, &block)
	end
end
