Gem::Specification.new do |s|
  s.name        = "splay-controller"
  s.version     = "##VERSION##"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Pascal Felber","Etienne Riviere","Valerio Schiavoni","Jose Valerio"]
  s.email       = ["info@splay-project.org"]
  s.homepage    = "http://www.splay-project.org/"
  s.summary     = "The Splay controller gives order to the Splay daemons."
  s.description = "The Splay controller gives order to the Splay daemons to instantiates the application, and to apply dynamics-related operations (starting, stopping, monitoring an application, as well as churn management)."
  s.required_rubygems_version = ">= 1.3.7"
  s.add_dependency("openssl-nonblock", [">=0.2.1"])
  s.add_dependency("json", [">=1.4.6"])
  s.add_dependency("dbi", [">=0.4.5"])
  s.add_dependency("dbd-mysql", [">=0.4.4"])
  s.add_dependency("mysql", [">=2.8.1"])
  s.add_dependency("openssl-nonblock", [">=0.2.1"])
  s.files        = Dir.glob("{bin,lib,daemons}/**/*") + %w(controller.rb controller_fork.rb init_db.rb COPYING COPYRIGHT)
  s.executables  = ['splay-controller.sh','splay-controller-fork.sh','splay-init_db.sh']
  s.has_rdoc = false
  s.license = 'GPL-3'
end
