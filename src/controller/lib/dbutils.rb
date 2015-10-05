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


require 'sequel' 
require 'mysql2'

class DBUtils
    
	def self.get_new_mysql_sequel
		if $log then
      $log.info("New DB connection (Sequel+MySQL)")
    end
		db = Sequel.connect("mysql://#{SplayControllerConfig::SQL_USER}:#{SplayControllerConfig::SQL_PASS}@#{SplayControllerConfig::SQL_HOST}:#{SplayControllerConfig::SQL_PORT}/#{SplayControllerConfig::SQL_DB}")
		#db.autocommit(false) -- not supported by Sequel adapter for mysql ?
    class << db 
      alias :do :run
    end		
		return db
	end
  
  def self.get_new_sqlite
		$log.info("New DB connection (Sequel + InMemory SQLite)")    
    db = Sequel.sqlite
    return db
  end
end
