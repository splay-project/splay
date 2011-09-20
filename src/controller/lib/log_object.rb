## Splay Controller ### v1.1 ###
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
