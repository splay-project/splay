## Splay Controller ### v1.3 ###
## Copyright 2006-2011
## http://www.splay-project.org
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

# Lightweight JSON-RPC over HTTP Service for SPLAY controller in Ruby
# Created by Valerio Schiavoni

require 'webrick'
require 'json'
require File.expand_path(File.join(File.dirname(__FILE__), 'controller-api'))
class SplayCtrlApiBroker < WEBrick::HTTPServlet::AbstractServlet 
  @@ctrl_api = Ctrl_api.new
  def do_POST(request, response)
    json_request=JSON.parse(request.body)
    method=json_request['method'].split( '.' )[1] 
    params=json_request['params']
    begin
      if  params !=nil then
        if params.size < 1
          result = @@ctrl_api.send(method)                   
        else
          result = @@ctrl_api.send(method,*params)
        end
      else
        result = @@ctrl_api.send(method)
      end
      error = nil
    rescue
      result = nil
      error = $!.to_s
    end
    response['Content-Type'] = request.content_type
    response.body = "{'result':#{JSON.unparse(result)}}"
  end
end
if $0 == __FILE__ then
  server = WEBrick::HTTPServer.new(:Port => 2222)
  server.mount "/splay-ctrl-api", SplayCtrlApiBroker
  trap "INT" do server.shutdown end
  server.start
end
