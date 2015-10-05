require "minitest/autorun"

require File.expand_path(File.join(File.dirname(__FILE__), '../lib/db_config'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/dbutils'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/config'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/splayd'))

require 'logger' # Logger::Error

class TestSplayd < Minitest::Test
  
  def setup
    $db = DBUtils::get_new_mysql_sequel
    $log = Logger.new(STDERR)
    $log.level = Logger::DEBUG   
  end
  
  def test_initalize
    nb_splayds_before = $db[:splayds].all.size
    s= Splayd.new('host_1_1')
    nb_splayds_after = $db[:splayds].all.size
    assert_equal(nb_splayds_after, nb_splayds_before+1, "Expected 1 splayd but was #{nb_splayds_after}")
  end
  
  def test_init
    $db[:splayds].insert(:id=>3, key=> 'test_host',:status=>'AVAILABLE')
    Splayd.init()
  end
  
end