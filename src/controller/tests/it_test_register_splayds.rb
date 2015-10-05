require "minitest/autorun"

require File.expand_path(File.join(File.dirname(__FILE__), '../lib/db_config'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/dbutils'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/config'))

require 'logger' # Logger::Error

class IntegrationTestRegisterSplayds < Minitest::Test
  
  def setup
    IO.popen("cp ../../daemon/splayd.lua it_tests_files/")
    IO.popen("sed -i -e s/\"production = true\"/\"production = false\"/ it_tests_files/splayd.lua")
    
    IO.popen("cp ../../daemon/jobd.lua it_tests_files/")
     
    $db = DBUtils::get_new_mysql_sequel
    $log = Logger.new(STDERR)
    $log.level = Logger::DEBUG
    #start the controller
    @ctrl_pipe = IO.popen("ruby -rubygems ../controller.rb")   
  end
  
  
  def test_register
   sleep 2 #wait for the controller to boot
   @splayd_pipe = IO.popen("cd it_tests_files && lua splayd.lua host_test_register 127.0.0.1 11000 14000 14999")
   sleep 2
   refute_nil $db[:splayds].first(:key=>'host_test_register') 
  end
  
 
  def teardown
   $db[:splayds].where(:key=>'host_test_register').delete  
    
   IO.popen("kill -9 #{@ctrl_pipe.pid}")
   IO.popen("kill -9 #{@splayd_pipe.pid}")
   IO.popen("killall lua")
   
   IO.popen("rm it_tests_files/splayd.lua")
   IO.popen("rm it_tests_files/splayd.lua-e") #created by sed
   IO.popen("rm it_tests_files/jobd.lua")
   
   IO.popen("rm -rf it_tests_files/jobs/")
   IO.popen("rm -rf it_tests_files/jobs_fs/")
   IO.popen("rm -rf it_tests_files/libs_cache/")
   IO.popen("rm -rf it_tests_files/logs/")   
  end
  
end