## Splay Controller ### v1.1.1 ###
## Copyright 2006-2011
## http://www.splay-project.org
## 
## 
## 
## This file is part of Splay.
## 
## Splayd is free software: you can redistribute it and/or modify 
## it under the terms of the GNU General Public License as published 
## by the Free Software Foundation, either version 3 of the License, 
## or (at your option) any later version.
## 
## Splayd is distributed in the hope that it will be useful,but 
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
## See the GNU General Public License for more details.
## 
## You should have received a copy of the GNU General Public License
## along with Splayd. If not, see <http://www.gnu.org/licenses/>.

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
