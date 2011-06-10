require 'thread'

# Distributed DB locking, for locks between different hosts (or different local
# instance, even if it's not the most efficient way in that case).
class DistributedLock

	@@mutex = Mutex.new
	@@db = nil

	def initialize(name)
		@name = name
		@lock = false
	end

	def get()
		return DistributedLock::get(@name)
	end

	def release()
		return DistributedLock::release(@name)
	end

	def self.get(name)
		if not @@db then @@db = DBUtils.get_new end
		ok = false
		while not ok
			@@mutex.synchronize do
			# TO TEST (transaction) or watch code, must be a Mutex like mine... +
			# BEGIN and COMMIT
			#$dbt.transaction do |dbt|
				@@db.do "BEGIN"
				locks = @@db.select_one("SELECT * FROM locks
							WHERE id='1' FOR UPDATE")
				if locks[name]
					if locks[name] == 0
						@@db.do "UPDATE locks SET #{name}='1' WHERE id ='1'"
						ok = true
					end
				else
					$log.error("Trying to get a non existant lock: #{name}")
					ok = true
				end
				@@db.do "COMMIT"
			end
		end
	end

	def self.release(name)
		@@mutex.synchronize do
			#@@db.do "BEGIN"
			@@db.do "UPDATE locks SET #{name}='0' WHERE id ='1'"
			#@@db.do "COMMIT"
		end
	end
end
