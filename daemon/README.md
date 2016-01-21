#SPLAY Daemon
[![Build Status](https://travis-ci.org/raziel-carvajal/splay-daemon.svg?branch=master)](https://travis-ci.org/raziel-carvajal/splay-daemon)

#Prerequisites
Some dependencies are required before the compilation and installation of Splay Daemon, please, follow the next steps according to your system.

##GNU-Linux Based Systems

###Debian 8.2

```sudo apt-get install gcc make lua5.2 liblua5.2 liblua5.2-dev libssl-dev lua-socket lua-sec openssl```

###Ubuntu LTS 14.04 and 15.04
Install these prerequisites via Ubuntu's package manager:

```sudo apt-get install lua5.2 liblua5.2 liblua5.2-dev libssl-dev lua-socket lua-sec openssl```


##Mac OS X 10.7 (Lion), 10.10 (Yosemite) and 10.11 (El Capitan)
Firstly, you must have [Xcode](http://developer.apple.com/xcode/) and [Homebrew](http://brew.sh/) installed in your system. Homebrew's installation is done through the next command:

```ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"```

Secondly, Splay Daemon prerequisites are installed via Homebrew's and Lua's package manager in three steps:

1. ```brew install lua openssl```

1. ```sudo luarocks-5.2 install luasec OPENSSL_DIR=/usr/local/opt/openssl```

1. ```sudo luarocks-5.2 install luasocket```

#Compilation and Installation
The last tarball of Splay Daemon ready to download is located [here](https://github.com/splay-project/splay/raw/master/daemon/dist/splay-daemon-1.0.tar.gz). Once the file is downloaded, decompress the taball as follows:

```tar xzvf splay-daemon-1.0.tar.gz```

In ```splay-daemon-1.0``` you will find the script ```configure``` to help ```make``` with the compilation, installation and test of Splay Deamon. Depending on your system, the ```configure``` script must be launch as follows:

- GNU-Linux: ```./configure --with-luabase64```
- OS X: ```./configure --with-luabase64 --enable-lua-headers=/usr/local/include --enable-lua-library=/usr/local/lib```

By default Splay Daemon is installed on your ```$HOME``` directory, if you want to change the installation directory just add the option ```--prefix=/here/your/installation/directory``` when you launch the ```configure``` script.

Now you compile Splay Daemon typing the command ```make``` and install it with ```make install```. To test your installation just type ```make test_splay-daemon```, you will see an output as follows:

```
------------- start testing installation -------------
------------- end testing installation -------------
If there is no error messages, all the required libraries are
installed and found on this system

```

##Additional options in ```configure```
Splay Daemon uses [GNU Autotools](http://www.gnu.org/software/autoconf/autoconf.html) to be built, apart from the options that the script ```configure``` has by default, the next options were added:

```
Optional Features:
--enable-lua-headers=Dir
Directory where Lua headers are located, by default
this argument is empty
--enable-lua-library=Dir
Directory where the Lua library is located, by
default this argument is empty
--enable-openssl-library=Dir
Directory where the OpenSsl library is located, by
default this argument is empty
--enable-crypto-library=Dir
Directory where the Crypto library is located, by
default this argument is empty
Optional Packages:
--with-luabase64
Compile base64 library for Lua5.2
```

If you have installed the headers files of Lua and the libraries of Lua, Openssl or Crypto in a different location, you have to add (with the right directories) the last options when you run ```configure``` .
