require "minitest/autorun"
require File.expand_path(File.join(File.dirname(__FILE__), '../init_db'))

class TestInitDb < Minitest::Test
  
  def setup
  end
   
  def test_drop_sqlite
    @db = DBUtils::get_new_sqlite
    refute_nil(@db)
    
    #monkey-patch to keep backward compatibility
    class << @db 
      alias :do :run
    end    
    
    drop_db(@db)
    init_db(@db)
    self.check_tables(@db)
  end
  
  def test_drop_mysql
    @db = DBUtils::get_new_mysql_sequel
    refute_nil(@db)
    drop_db(@db)
    init_db(@db)
    self.check_tables(@db)
  end
  
  def check_tables(db)
      assert(@db[:actions])
      assert(@db[:blacklist_hosts])
      assert(@db[:jobs_designated_splayds])
      assert(@db[:jobs_mandatory_splayds])
      assert(@db[:jobs])
      assert(@db[:libs])
      assert(@db[:local_log])
      assert(@db[:locks])
      assert(@db[:splayds_availabilities])
      assert(@db[:splayds_jobs])
      assert(@db[:splayds_libs])
      assert(@db[:splayds_selections])
      assert(@db[:splayds])
  end
  
end