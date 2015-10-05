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
    s= Splayd.new('test_initialize')
    nb_splayds_after = $db[:splayds].all.size
    assert_equal(nb_splayds_after, nb_splayds_before+1, "Expected 1 splayd but was #{nb_splayds_after}")
  end
  
  def test_check_and_set_preavailable
    s= Splayd.new('test_check_and_set_preavailable')    
    res = s.check_and_set_preavailable
    assert(res==true, "Result of check_and_set_preavailable expected to be true but was #{res}")
    status = $db[:splayds].where(:key=>'test_check_and_set_preavailable').get(:status)
    assert_equal('PREAVAILABLE',status)
  end
  
  def test_init
      s= Splayd.new('test_splayd_init')
      s.check_and_set_preavailable
      Splayd.init
      status = $db[:splayds].where(:key=>'test_splayd_init').get(:status)          
  end
  
  def teardown
    $db[:splayds].where(:key=>'test_init_host').delete
    $db[:splayds].where(:key=>'test_initialize').delete
    $db[:splayds].where(:key=>'test_check_and_set_preavailable').delete
    $db[:splayds].where(:key=>'test_splayd_init').delete
  end
  
end