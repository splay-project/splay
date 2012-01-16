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

require 'net/http'
require 'resolv'
require 'timeout'
require 'logger'

if not $log
	$log = Logger.new(STDERR)
	$log.level = Logger::INFO
	$log.datetime_format = "%H:%M:%S "
end

class Localization

	@@ip_url = 'http://devel.unipix.ch/ip.php'
	@@base_url = 'http://geoip1.maxmind.com/b?l=lzCyxlYoTu5z&i='
	
	attr_reader :hostname, :country, :city, :latitude, :longitude

	@hostname = nil
	@country = nil
	@city = nil
	@latitude = nil
	@longitude = nil

	def initialize(ip)
		# We'll try to find our public IP
		if ip == "127.0.0.1"
			begin
				response = Net::HTTP.get_response(URI.parse(@@ip_url))
				ip = response.body.strip
			rescue => e
				$log.error(e.class.to_s + ": " + e.to_s)
				return
			end
			if not ip =~ /[^\.]*\.[^\.]*\.[^\.]*\.[^\.]*/ or ip == "127.0.0.1"
				$log.error("Localization of local ip impossible.")
				return
			end
		end

		begin
			Timeout::timeout(5, StandardError) do
				@hostname = Resolv::getname(ip)
			end
		rescue => e
			$log.error(e.class.to_s + ": " + e.to_s)
		end

		r = nil
		begin
			response = Net::HTTP.get_response(URI.parse("#{@@base_url}#{ip}"))
			r = response.body
		rescue => e
			$log.error(e.class.to_s + ": " + e.to_s)
			return
		end

		# DK,(null),(null),56.000000,10.000000
		# CH,12,Neuchâtel,47.000000,6.966700
		# CH,12,La Chaux-de-fonds,47.133301,6.850000
		# US,TX,Dallas,32.782501,-96.820702
		# ,,,,,IP_NOT_FOUND
		# A1,(null),(null),0.000000,0.000000
		if r =~ /,,,,,(.*)/
			$log.error("Localization of #{ip} give error: #{$1}")
		elsif r =~ /([^,]*),[^,]*,([^,]*),([^,]*),(.*)/
#       puts $1, $2, $3, $4
			if $1 != "(null)"
				@country = $1.downcase
			end
			# TODO iso to utf8
			if $2 != "(null)"
				@city = $2
			end
			if $3 != "(null)"
				@latitude = $3
			end
			if $4 != "(null)"
				@longitude = $4
			end
			# special case...
			if @country == "a1" and @latitude == "0.000000" and @longitude == "0.000000"
				@country = nil
				@latitude = nil
				@longitude = nil
			end
		else
			$log.error("Localization of #{ip} give a strange string: #{r}")
		end
	end

	def self.run
		return Thread.new do
			Splayd.localize_all
		end
	end

	# http://www.iso.org/iso/country_codes/iso_3166_code_lists/english_country_names_and_code_elements.htm
	def self.countries
		countries = {}
		countries['af'] = ['ao', 'bf', 'bi', 'bj', 'bw', 'cd', 'cf', 'cg', 'ci', 'cm',
		'cv', 'dj', 'dz', 'eg', 'eh', 'er', 'et', 'ga', 'gh', 'gm', 'gn', 'gq', 'gw',
		'ke', 'km', 'lr', 'ls', 'ly', 'ma', 'mg', 'ml', 'mr', 'mu', 'mw', 'mz', 'na',
		'ne', 'ng', 're', 'rw', 'sc', 'sd', 'sh', 'sl', 'sn', 'so', 'st', 'sz', 'td',
		'tg', 'tn', 'tz', 'ug', 'yt', 'za', 'zm', 'zw']
		countries['an'] = ['aq', 'bv', 'gs', 'hm', 'tf'] 
		countries['as'] = ['ae', 'af', 'am', 'az', 'bd', 'bh', 'bn', 'bt', 'cc', 'cn',
		'cx', 'cy', 'ge', 'hk', 'id', 'il', 'in', 'io', 'iq', 'ir', 'jo', 'jp', 'kg',
		'kh', 'kp', 'kr', 'kw', 'kz', 'la', 'lb', 'lk', 'mm', 'mn', 'mo', 'mv', 'my',
		'np', 'om', 'ph', 'pk', 'ps', 'qa', 'sa', 'sg', 'sy', 'th', 'tj', 'tl', 'tm',
		'tr', 'tw', 'uz', 'vn', 'ye']
		countries['eu'] = ['ad', 'al', 'at', 'ax', 'ba', 'be', 'bg', 'by', 'ch', 'cz',
		'de', 'dk', 'ee', 'es', 'fi', 'fo', 'fr', 'gb', 'gg', 'gi', 'gr', 'hr', 'hu',
		'ie', 'im', 'is', 'it', 'je', 'li', 'lt', 'lu', 'lv', 'mc', 'md', 'me', 'mk',
		'mt', 'nl', 'no', 'pl', 'pt', 'ro', 'rs', 'ru', 'se', 'si', 'sj', 'sk', 'sm',
		'ua', 'va']
		countries['na'] = ['ag', 'ai', 'an', 'aw', 'bb', 'bm', 'bs', 'bz', 'ca', 'cr',
		'cu', 'dm', 'do', 'gd', 'gl', 'gp', 'gt', 'hn', 'ht', 'jm', 'kn', 'ky', 'lc',
		'mq', 'ms', 'mx', 'ni', 'pa', 'pm', 'pr', 'sv', 'tc', 'tt', 'us', 'vc', 'vg',
		'vi']
		countries['oc'] = ['as', 'au', 'ck', 'fj', 'fm', 'gu', 'ki', 'mh', 'mp', 'nc',
		'nf', 'nr', 'nu', 'nz', 'pf', 'pg', 'pn', 'pw', 'sb', 'tk', 'to', 'tv', 'um',
		'vu', 'wf', 'ws']
		countries['sa'] = ['ar', 'bo', 'br', 'cl', 'co', 'ec', 'fk', 'gf', 'gy', 'pe',
		'py', 'sr', 'uy', 've']
		return countries
	end
end
