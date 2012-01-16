## Splayweb ### v1.1 ###
## Copyright 2006-2011
## http://www.splay-project.org
## 
## 
## 
## This file is part of Splayd.
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


class MapController < ApplicationController

	layout 'default'
	before_filter :login_required

	def index
		@g_splayds = SplaydController::array_for_map
		@registered = Splayd.find(:all)
		@available = Splayd.find(:all, :conditions => "status = 'AVAILABLE'")
		@unavailable = Splayd.find(:all, :conditions => "status = 'UNAVAILABLE'")
		@reset = Splayd.find(:all, :conditions => "status = 'RESET'")
	end

	def map_job
	end

	def map_splayd

	end
end
