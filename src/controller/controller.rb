#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), 'lib/common'))
# We force only one log daemon and one splayd daemon
SplayControllerConfig::NumLogd ||= 1
SplayControllerConfig::NumSplayd ||= 1

#require 'lib/all'
require File.expand_path(File.join(File.dirname(__FILE__), 'lib/all'))

#$log.level = Logger::DEBUG
$log.level = Logger::INFO

puts
puts ">>> Splayd Controller #{SplayControllerConfig::CTLVersion} <<<"
puts
puts "http://www.splay-project.org"
puts "Splay Controller is licensed under GPL v3, see COPYING"
puts

Splayd.init
$db.do "UPDATE locks SET job_reservation='0' WHERE id ='1'"

# Daemons
LogdServer.new.run
SplaydServer.new.run
JobdStandard.run

if SplayControllerConfig::AllowNativeLibs
  JobdGrid.run
end

JobdTrace.init

JobdTraceAlt.run
Unseend.run
Statusd.run
Loadavgd.run
Blacklistd.run

#Splayd.localize_all

# end only on interruption
loop do sleep 1000 end
