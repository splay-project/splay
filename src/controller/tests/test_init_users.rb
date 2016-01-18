require "minitest/autorun"
require File.expand_path(File.join(File.dirname(__FILE__), '../init_users'))

class TestInitUsers < Minitest::Test
  
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
      assert(@db[:users])    
      
      admin = @db[:users][:id=>1] #the first and should be the only user
      assert(admin)
  end
  
end