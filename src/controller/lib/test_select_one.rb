#!/usr/bin/env ruby
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/common'))
$db = DBUtils.get_new
begin
  $db.select_one "SELECT * FROM splayds WHERE `key`='host_1_1'" 
rescue TypeError => e
  puts "rescued: #{e}"  
end