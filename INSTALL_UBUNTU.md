##Instructions for Ubuntu 14.04 LTS

###The quick way

```
curl -sfL https://raw.githubusercontent.com/splay-project/splay/master/ubuntu_inst.sh | sh
```

###Step-by-step
Install the dependencies to compile and install Splay from source:

```bash
sudo apt-get install git build-essential libreadline-dev libncurses5-dev \
lua5.1 liblua5.1-0 liblua5.1-0-dev lua-socket lua-socket-dev \
libssl-dev lua-sec lua-sec-dev 
```

Append the following at the bottom of your $HOME/.bashrc:
```bash
SPLAY_PATH="$HOME/local/lualibs/lib/?.lua"
SPLAY_CPATH="$HOME/local/lualibs/clib/?.so"
DEFAULT_LUA_PATH=`lua -e "print( package.path)"`
DEFAULT_LUA_CPATH=`lua -e "print( package.cpath)"`
LUA_PATH="$SPLAY_PATH;$DEFAULT_LUA_PATH"
LUA_CPATH="$SPLAY_CPATH;$DEFAULT_LUA_CPATH"
export LUA_PATH LUA_CPATH
```
These instructions append the installation paths of the Splay libraries to the default path. It uses the Lua interpreter to get the current system's path.

Then, proceed with the following steps:
```bash
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make linux
cd ../../daemon/
make
source ~/.bashrc
./install.sh
```

You are now ready to Splay!

