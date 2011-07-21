## Splay Controller ### v1.0.7 ###
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


class Loadavgd
	@@loadavg_interval = SplayControllerConfig::LoadavgInterval
	def self.run
		return Thread.new do
			main
		end
	end
	def self.main
		begin
			$log.info(">>> Splay Controller Loadavg Daemon")
			while sleep(@@loadavg_interval)
				$db.select_all "SELECT id FROM splayds WHERE status='AVAILABLE'" do |splayd|
					$db.do "INSERT INTO actions SET
							splayd_id='#{splayd['id']}',
							command='LOADAVG'"
				end
			end
		rescue => e
			$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
		end
	end
end
