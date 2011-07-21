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

#Copy the file GeoLiteCity.dat in the same directory as this file.
#You can retrive a copy of it from http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
#Remember to decompress the file!
require 'geoip' ##install it with gem install geoip
class Localization

	@@loc_db = nil
	def self.get(ip)
		if not @@loc_db
			@@loc_db = GeoIP.new("#{File.dirname(__FILE__)}/GeoLiteCity.dat")
		end
		return @@loc_db.city(ip) # GeoIP::Record.new(@@loc_db, ip)
	end
end
