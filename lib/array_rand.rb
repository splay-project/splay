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
