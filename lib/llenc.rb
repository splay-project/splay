## Splay Controller ### v1.0.6 ###
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


# NOTE
# why socket.read can return a nil element and do not raise an exception when
# the connection is closed ?
#
# If we don't want a timeout, we set a very big value for timeout but I think
# it would be better to avoid that.

class LLencError < SocketError; end

class LLenc

	def initialize socket
		@socket = socket
		@read_timeout = @write_timeout = 24 * 3600
		@ip = @socket.peeraddr[3]
	end

	def set_timeout time
		@read_timeout = @write_timeout = time
	end

	def peeraddr
		return @socket.peeraddr
	end

	def _log msg
		if $log
			$log.debug "LLenc (#{@ip}): #{msg}"
		end
	end

	def write datas
		_log ">>> #{datas}"
		
		Timeout::timeout(@write_timeout, StandardError) do
			@socket.write(datas.length.to_s + "\n" + datas)
		end
	end

	def read(max = nil)

		Timeout::timeout(@read_timeout, StandardError) do

			length = @socket.readline.to_i
			if max and length > max
				raise LLencError, "data too long (#{dl} > #{max})"
			end

			t = @socket.read(length)
			if t.nil?
				raise LLencError, "data read error"
			end
			_log "<<< #{t}"
			return t
		end
	end
end
