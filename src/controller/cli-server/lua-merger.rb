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

#require '../lib/common.rb'
#library required for hashing
require 'digest/sha1'

#required for job decoding (.tar.gz)
require "base64"

#required for files unzipping
require 'zlib'
require 'archive/tar/minitar'
include Archive::Tar

require 'tmpdir'

class LuaMerger

	def visit(node, adj_matrix, visited, nodes, num_nodes, sorted_nodes)
		if (visited.include?(node) == false) then
			visited.push(node)
			for i in (0..num_nodes-1)
				if (adj_matrix[nodes.index(node)][i] == 1) then
					visit(nodes[i], adj_matrix, visited, nodes, num_nodes, sorted_nodes)
				end
			end
			sorted_nodes.push(node)
		end
	end

	def merge_lua_files(code,ret)
		code = Base64.decode64(code)
		#retrieve OS's temporary file path
		tmp_dir = Dir.tmpdir

		#generate temporary .tar.gz
		tmp_job_tar = Tempfile.new(['job','.tar.gz'],tmp_dir)
		tmp_job_tar.print(code)
		tmp_job_tar.flush 

		#generate temporary directory to untar
		tmp_job = File.basename(tmp_job_tar.path,".tar.gz")
		tmp_job_dir = Dir.mktmpdir(tmp_job)

		#untar
		tgz = Zlib::GzipReader.new(File.open(tmp_job_tar.path, 'rb'))
		Minitar.unpack(tgz, tmp_job_dir)
	
		#remove tar.gz
		tmp_job_tar.close
		tmp_job_tar.unlink

		#prepare for topological sorting of files
		#retrieve files (nodes) and associate them with indexes
		nodes = Array.new
		Dir[tmp_job_dir + "/*"].each { |file|
			nodes.push(File.basename(file,'.lua'))
		}
	
		#get the number of nodes without counting . and ..
		num_nodes = Dir.entries(tmp_job_dir).size - 2

		#adjacency matrix
		adj_matrix = Array.new(num_nodes){Array.new(num_nodes)}
		#initialize it with 0s
		for i in (0..num_nodes-1)
			for j in (0..num_nodes-1)
				adj_matrix[i][j] = 0
			end
		end
		#build it
		Dir[tmp_job_dir + "/*"].each { |file|
			file_name = File.basename(file,'.lua')
			file_index = nodes.index(file_name)
			f = File.new(file, "r")
			#identify adj_matrix
			while (line = f.gets) 
				if line.include? 'require' then
					line.strip!
					# isolate library name
					position = line.index("require")
					file2 = line[(position+8)..line.length-2] 
					if (nodes.include? file2) then
						#retrieve index for file2
						file2_index = nodes.index(file2)
						adj_matrix[file_index][file2_index] = 1
					end
				end
			end
			f.close()
		}

		#tmp
		aFile = File.new("/tmp/file", "w")
	
		#set of all nodes with no incoming edges
		no_incoming_edges = Array.new
		for i in (0..num_nodes-1)
			no_in_edges = false
			for j in (0..num_nodes-1)
				if (adj_matrix[i][j] == 1) then
					no_in_edges = true
				end
			end
			if (no_in_edges == true) then 
				no_incoming_edges.push(nodes[i])
			end
		end
	
		#topological sort
		visited = Array.new
		sorted_nodes = Array.new
		no_incoming_edges.each { |node|
			visit(node, adj_matrix, visited, nodes, num_nodes, sorted_nodes)
		}


		libraries = Array.new
		library_var = Hash.new(nil)
		functions = Hash.new(nil)
		functionsCode = Array.new
		global_vars = Hash.new(nil)
		local_vars = Hash.new(nil)

		#this will contain the merged file
		code = ""

		#merge
		#iterate through sorted files

		library_code = ""
		other_code = ""
		main_code = ""
		has_events_thread = false

		sorted_nodes.each { |file|
			file_path = tmp_job_dir + "/" + file + ".lua"
			file_handler = File.new(file_path, "r")
		
			#this hashmap stores all names (conflicts) that need to be replaced in the current file
			replace = Hash.new(nil)

			count_to_end = 0
			parser_is_in_function = false
			parser_is_in_main = false
			current_function_index = 0

			file_code = ""
			while (line = file_handler.gets)
			
				#remove all comments from the code
				if line.include? '--' then
					position = line.index("--")
					line = line[0..position]
				end

				trim_line = String.new(line)
				trim_line.strip!

				#add library
				#if line starts with "require", followed by whitespace or "
				if /^[ \t]*require[" \t]/.match(trim_line) != nil then
					# isolate library name
					position = trim_line.index("require")
					lib = trim_line[(position+7)..trim_line.length]
					#strip the quotes ("")
					lib = lib[1..lib.length]
					lib = lib[0..lib.index("\"")-1]
					lib.strip!
					#if it is not already included and not a file name
					if (!(libraries.include? lib) and !(nodes.include? lib)) then
						libraries.push(lib)
					end
					if ((libraries.include? lib) and !(nodes.include? lib)) then
						if (library_var[lib] != nil) then
							#error: same library included with different names
							ret['error'] = "module " + lib + " is allocated to two different variables: " + "nil" + " and " + library_var[lib]
							return "", ret
						end
					end
					next
				end

				#handle the case: x = require"lib"
				if /.+=[ \t]*require[" \t]/.match(trim_line) != nil then
					#trim to: x = 
					position = trim_line.index("require")
					lib = trim_line[(position+7)..trim_line.length]
					var_name = trim_line[0..position-1]
					#trim to: x
					position = trim_line.index("=")
					var_name = trim_line[0..position-1]
					#remove any "local"
					if /[^a-zA-Z_0-9]*local[^a-zA-Z_0-9]/.match(var_name) then
						var_name = var_name.sub(/[^a-zA-Z_0-9]*local[^a-zA-Z_0-9]/,"")
					end
					var_name.strip!
					#strip the quotes
					lib = lib[1..lib.length]
					lib = lib[0..lib.index("\"")-1]
					lib.strip!

					if (!(libraries.include? lib) and !(nodes.include? lib)) then
						libraries.push(lib)
						library_var[lib] = var_name
					end
					if ((libraries.include? lib) and !(nodes.include? lib)) then
						if (library_var[lib] != var_name) then
							#error: same library included with different names
							ret['error'] = "module " + lib + " is allocated to two different variables: " + var_name + " and " + library_var[lib]
							return "", ret
						end
					end
					next
				end

				if /^[ \t]*events\.thread[ (\t]/.match(trim_line) != nil then
					has_events_thread = true
				end

				#events.run
				if /^[ \t]*events\.run[ (\t]/.match(trim_line) != nil or /^[ \t]*events\.loop[ (\t]/.match(trim_line) != nil then
					#if main_code != "" then
						#ret['error'] = "" + trim_line + " conflicts with " + main_code
						#return "", ret
					#end
					#main_code = trim_line
					parser_is_in_main = true
				end

				#functions
				#search for named functions
				if ((trim_line.start_with? 'function') and /function[ \t]\(/.match(trim_line) == nil and parser_is_in_function == false and parser_is_in_main == false) then
					parser_is_in_function = true
					# isolate function name
					position = trim_line.index("(")
					func_name = trim_line[9..(position-1)]
					func_name.strip!
				
					#check if function already exists
					if ( functions[func_name] == nil ) then
						functions[func_name] = trim_line
						count_to_end = 0;
					else
						orig_func_name = func_name
						#find new name
						while(functions[func_name] != nil)
							func_name += "_"
						end
						functions[func_name] = 1
						replace[orig_func_name] = func_name
					end
				
					current_function_index = functionsCode.length
					functionsCode.push(line)

					file_code += line
					next
				end

				if (parser_is_in_main == true) then
					if /^[ \t]*events\.run[ (\t]/.match(trim_line) == nil and /^[ \t]*events\.loop[ (\t]/.match(trim_line) == nil and (/^[ \t]*end[ )\t]/.match(trim_line) == nil and count_to_end == 0) then
						main_code += line
					end
					next
				end

				if (parser_is_in_function == true) then
					functionsCode[current_function_index] += line
				end

				if ((parser_is_in_function == true or parser_is_in_main == true) and (trim_line.include? 'if' or line.include? 'while')) then
					count_to_end = count_to_end + 1
				end

				if ((parser_is_in_function == true or parser_is_in_main == true) and trim_line.include? 'end') then
					if (count_to_end > 0) then
						count_to_end = count_to_end - 1
					else
						parser_is_in_function = false
					end
				end

				if (parser_is_in_function == false and trim_line.include? '=' and /^[ \t]*local/.match(trim_line) == nil) then
					position = trim_line.index("=")
					vars_line = trim_line(0..position-1)
				
					vars = vars_line.split(',')
					vars.each { |var|
						var.strip!
						if (global_vars[var] == nil) then
							global_vars[var] = 1
						else
							orig_var = var
							#find new name
							while(global_vars[var] != nil)
								var += "_"
							end
							global_vars[var] = 1
							replace[orig_var] = var
						end
					}
				end

				if (parser_is_in_function == false and trim_line.include? '=' and /^[ \t]*local/.match(trim_line) != nil) then
					position = trim_line.index("=")
					vars_line = trim_line[0..position-1]
					position = trim_line.index("local")
					vars_line = vars_line[position+5..vars_line.length]

					vars = vars_line.split(',')
					vars.each { |var|
						var.strip!
						if (local_vars[var] == nil) then
							local_vars[var] = 1
						else
							orig_var = var
							#find new name
							while(local_vars[var] != nil)
								var += "_"
							end
							local_vars[var] = 1
							replace[orig_var] = var
						end
					}
				end

				file_code += line
			end
		
			#iterate each name we need to replace
			replace.each { |orig_name,new_name|
				#compute regular expression
				#a valid name is preceded by a character that is not a-z, A-Z, _, 0-9
				#and succeeded by a similar character
				regex = Regexp.new("[^a-zA-Z_0-9]" + orig_name + "[^a-zA-Z_0-9]")
				#find all instances of that regular expression
				file_code = file_code.gsub(regex) { |s|
					#replace the name in that instance
					s.sub(orig_name,new_name)
				}
				main_code = main_code.gsub(regex) { |s|
					#replace the name in that instance
					s.sub(orig_name,new_name)
				}
			
			}
			other_code += file_code
		}

		libraries.each{ |lib|
			if (library_var[lib] == nil) then
				library_code += "require\"" + lib + "\"\n"
			else
				library_code += "local " + library_var[lib] + "=require\"" + lib + "\"\n"
			end
		}

		#warning
		if (main_code.length == 0 and has_events_thread == false) then
			ret['error'] = "main function - events.run() or events.loop() - is missing"
			return "", ret
		end

		if (has_events_thread == true) then
			if (main_code.length > 0) then
				main_code = "events.thread(\n" + main_code + ")\nevents.run()\n"
			else
				main_code = "events.run()\n"
			end
		else
			main_code = "events.run(\n" + main_code + ")\n"
		end

		aFile.write(library_code)
		aFile.write(other_code)
		aFile.write(main_code)
		code = library_code + other_code + main_code
		aFile.close()
		#remove tmp dir
		FileUtils.remove_entry_secure tmp_job_dir

		return code, ret
	end
end
