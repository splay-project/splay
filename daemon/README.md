#SPLAY Daemon
[![Build Status](https://travis-ci.org/raziel-carvajal/splay-daemon.svg?branch=master)](https://travis-ci.org/raziel-carvajal/splay-daemon)

#1. Prerequisites
Some dependencies are required before the compilation and installation of SplayDaemon, please, follow the next steps according to your system.

##GNU-Linux Based Systems

###Debian 8.2
Install required packages typing as follows:

```sudo apt-get install gcc make lua5.2 liblua5.2 liblua5.2-dev libssl-dev lua-socket lua-sec openssl```

###Ubuntu LTS 14.04 and 15.04
Install required packages typing as follows:

```sudo apt-get install lua5.2 liblua5.2 liblua5.2-dev libssl-dev lua-socket lua-sec openssl```


##Mac OS X 10.7 (Lion), 10.10 (Yosemite) and 10.11 (El Capitan)
Firstly, you must have [Xcode](http://developer.apple.com/xcode/) and [Homebrew](http://brew.sh/) installed on your system. Particularly, the installation of Homebrew is done as follows:

```ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"```

Secondly, SplayDaemon prerequisites are installed using Homebrew and the package manager of Lua as follows:

1. ```brew install lua openssl```

1. ```sudo luarocks-5.2 install luasec OPENSSL_DIR=/usr/local/opt/openssl```

1. ```sudo luarocks-5.2 install luasocket```

#2. Compilation and Installation
Clic [here](https://github.com/splay-project/splay/raw/master/daemon/dist/splay-daemon-1.0.tar.gz) to download the stable version of SplayDaemon. Once the file is downloaded, decompress it as follows:

```tar xzvf splay-daemon-1.0.tar.gz```

At the directory ```splay-daemon-1.0``` you will find the script ```configure``` to help ```make``` with the compilation, installation and test of SplayDeamon. Depending on your system, the ```configure``` script must be launch as follows:

- GNU-Linux: ```./configure --with-luabase64```
- OS X: ```./configure --with-luabase64 --enable-lua-headers=/usr/local/include --enable-lua-library=/usr/local/lib```

By default Splay Daemon is installed on your ```$HOME``` directory, if you want to change the installation directory just add the option ```--prefix=/here/your/installation/directory``` when you launch the ```configure``` script.

Now you compile Splay Daemon typing the command ```make``` and then install it with ```make install```. To test your installation just type ```make test_splay-daemon```, you will see an output as follows:

```
------------- start testing installation -------------
------------- end testing installation -------------
If there is no error messages, all the required libraries are
installed and found on this system

```

##Additional options in ```configure```
SplayDaemon uses [GNU Autotools](http://www.gnu.org/software/autoconf/autoconf.html) to be build, apart from the options that the script ```configure``` has by default, the next options were added:

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

#3. Having multiple clients
SplayDaemon's are clients that instantiate virtual nodes of your distributed application, depending on the resources of your computer you can have more than one of this clients. To have copies of a SplayDaemon launch the next `make` target as follows:
 
`make ARGS="LOCATION_DIR NUMBER_OF_DAEMONS SPLAY-CONTROLLER_IP SPLAY-CONTROLLER_DEAMONS-PORT" clone-daemons`

and here you have an explanation of the required arguments:

- `LOCATION_DIR` valid directory where SplayDaemons will be cloned
- `NUMBER_OF_DAEMONS` number of SplayDaemons
- `SPLAY-CONTROLLER_IP` IP address of the SplayController ([here](https://github.com/splay-project/splay) you will find more details about the role of SplayController)
- `SPLAY-CONTROLLER_DEAMONS-PORT` port number where the SplayController listens SplayDaemons

As a first step, it is recommended to have both Controller and Deamon on the same computer (if the controller is in a different computer you just have to set the right IP address for the argument `SPLAY-CONTROLLER_IP`). Here you have an example of how to clone deamons:

`make ARGS="~/MyDaemons 10 127.0.0.1 11000" clone-daemons`

Additionally, at the directory `LOCATION_DIR` you will find two scripts `launch-daemons.sh` and `stop-daemons.sh` to launch and stop every clone respectively. 