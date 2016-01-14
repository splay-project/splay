#SPLAY Daemon

#Prerequisites
Some dependencies are required before the compilation and installation of Splay Daemon, please, follow the next steps according to your system.

##GNU-Linux Based Systems

###Ubuntu Vivid Vervet (15.04)
Install these prerequisites via Ubuntu's package manager:

```sudo apt-get install lua5.2 liblua5.2 liblua5.2-dev lua-socket lua-sec openssl```


##OS X El Capitan (10.11)
Firstly, you must have [Xcode](http://developer.apple.com/xcode/) and [Homebrew](http://brew.sh/) installed in your system. Homebrew's installation is done through the next command:

```ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"```

Secondly, Splay Daemon prerequisites are installed via Homebrew's and Lua's package manager in three steps:

1. ```brew install lua openssl```

1. ```sudo luarocks-5.2 install luasec OPENSSL_DIR=/usr/local/opt/openssl```

1. ```sudo luarocks-5.2 install luasocket```

#Compilation and Installation
Download the latest distribution of Splay Daemon [here](https://github.com/splay-project/splay/blob/autoconfig/daemon/dist/splay-daemon-1.0.tar.gz)