require"rdbi"
require"rdbi-driver-mysql"
args = {
      :host     => "localhost",
      :hostname => "localhost",
      :port     => 3306,
      :username => "splay",
      :password => "splay",
      :database => "splay"
    }
db = RDBI.connect(:MySQL,args)