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

# http://www.rabbitcreative.com/ruby/articles/randomize-an-array-in-ruby/

class Array
	def randomize
		duplicated_original, new_array = self.dup, self.class.new
		new_array << duplicated_original.slice!(rand(duplicated_original.size)) until new_array.size.eql?(self.size)
		new_array
	end

	# ultra-fast but destroy the original array
#     def randomize
#         original_size, new_array = size, self.class.new
#         until new_array.size.eql?(original_size)
#             new_array << self.slice!(rand(size))
#         end
#         new_array
#     end

	def randomize!
		self.replace(randomize)
	end
end
