## Splay Controller ### v1.3 ###
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

class JobdGrid < JobdStandard        
  
	def self.get_scheduler
		return 'grid'
	end
	
	def self.create_filter_query(job)

		version_filter = ""
		if job['splayd_version']
			version_filter += " AND version='#{job['splayd_version']}' "
		end

		distance_filter = ""
		if job['distance'] and job['latitude'] and job['longitude']
			distance_filter =
					" AND longitude IS NOT NULL AND latitude IS NOT NULL AND
				DEGREES(
					ACOS(
						(
							SIN(RADIANS(#{job['latitude']})) * SIN(RADIANS(latitude))
						)
						+
						(
							COS(RADIANS(#{job['latitude']}))
							*
							COS(RADIANS(latitude))
							*
							COS(RADIANS(#{job['longitude']} - longitude))
						)
					) * 60 * 1.1515 * 1.61
				) <= '#{job['distance']}'  "
		end

		localization_filter = ""
		if job['localization']
			# If its a continent code.
			countries = countries_by_continent()
			if countries[job['localization']]
				localization_filter = " AND ("
				countries[job['localization']].each do |country|
					localization_filter += "country='#{country}' OR "
				end
				localization_filter = localization_filter[0..(localization_filter.length() - 5)] + ") "
			else
				localization_filter += " AND country='#{job['localization']}' "
			end
		end

		bytecode_filter = ""
		if job['code'][0,4] =~ /\x1BLua/ # Lua Bytecode
			if job['code'][0,5] =~ /\x1BLuaQ/
				bytecode_filter = " AND endianness='#{job['endianness']}' "
				bytecode_filter += " AND bits='#{job['bits']}' "
			else
				status_msg += "The bytecode isn't Lua 5.1 bytecode.\n"
				set_job_status(job['id'], 'NO_RESSOURCES', status_msg)
				next
			end
		end

		hostmasks_filter = ""
		if job['hostmasks']
			# TODO split with "|"
			hm_t = job['hostmasks'].gsub(/\*/, "%")
			hostmasks_filter = " AND (ip LIKE '#{hm_t}' OR hostname LIKE '#{hm_t}') "
		end

		resources_filter = "AND (splayds.status='AVAILABLE') AND
					max_mem >= '#{job['max_mem']}' AND
					disk_max_size >= '#{job['disk_max_size']}' AND
					disk_max_files >= '#{job['disk_max_files']}' AND
					disk_max_file_descriptors >= '#{job['disk_max_file_descriptors']}' AND
					network_max_send >= '#{job['network_max_send']}' AND
					network_max_receive >= '#{job['network_max_receive']}' AND
					network_max_sockets >= '#{job['network_max_sockets']}' AND
					network_max_ports >= '#{job['network_nb_ports']}' AND
					network_send_speed >= '#{job['network_send_speed']}' AND
					network_receive_speed >= '#{job['network_receive_speed']}' AND
					load_5 <= '#{job['max_load']}' AND
					start_time <= '#{Time.now.to_i - job['min_uptime']}' AND
					max_number > 0 "

		# We don't take splayds already mandatory (see later)
		mandatory_filter = ""
		$db.select_all "SELECT * FROM job_mandatory_splayds
				WHERE job_id='#{job['id']}'" do |mm|
			mandatory_filter += " AND splayds.id!=#{mm['splayd_id']} "
		end

		lib_filter = "AND libs.lib_name='#{job['lib_name']}' AND
                  libs.lib_version='#{job['lib_version']}' AND
                  libs.lib_arch=splayds.architecture AND
                  libs.lib_os=splayds.os AND
                  splayds.protocol='grid'"
    puts "LibFilter: #{lib_filter}"
		return "SELECT splayds.* FROM splayds,libs WHERE
				1=1
				#{version_filter}
				#{resources_filter}
				#{localization_filter}
				#{bytecode_filter}
				#{mandatory_filter}
				#{hostmasks_filter}
				#{distance_filter}
				#{lib_filter}
				ORDER BY RAND()"
	end
	

	def self.create_job_json(job)
		new_job = {}
		new_job['ref'] = job['ref']
		new_job['code'] = job['code']
		
		new_job['lib_name'] = job['lib_name']
		new_job['lib_version'] = job['lib_version']
			
		new_job['script'] = job['script']
		new_job['network'] = {}
		new_job['network']['max_send'] = job['network_max_send']
		new_job['network']['max_receive'] = job['network_max_receive']
		new_job['network']['max_sockets'] = job['network_max_sockets']
		new_job['network']['nb_ports'] = job['network_nb_ports']
		if job['udp_drop_ratio'] != 0
			new_job['network']['udp_drop_ratio'] = job['udp_drop_ratio']
		end
		new_job['disk'] = {}
		new_job['disk']['max_size'] = job['disk_max_size']
		new_job['disk']['max_files'] = job['disk_max_files']
		new_job['disk']['max_file_descriptors'] = job['disk_max_file_descriptors']
		new_job['max_mem'] = job['max_mem']
		new_job['keep_files'] = job['keep_files']
		new_job['die_free'] = job['die_free']
		return new_job.to_json
	end  
end
