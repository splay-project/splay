# first attempt at making a docker image for the splayd. 
# try it from the splay folder with: docker build -t etienne/ubuntu-splayd .
# it is still not functional at the moment, wip.
FROM	ubuntu:14.04.2
# install dependencies
RUN		apt-get update
RUN		apt-get install -y git build-essential libreadline-dev libncurses5-dev lua5.1 liblua5.1-0 liblua5.1-0-dev lua-socket lua-socket-dev libssl-dev lua-sec lua-sec-dev 
# copy the source code for the daemon
COPY	splay/src /splay/src
# install app dependencies
# empty for now
# set the dependencies
RUN echo "SPLAY_PATH=\"$HOME/local/lualibs/lib/?.lua\"" 		>> ~/.bashrc
RUN echo "SPLAY_CPATH=\"$HOME/local/lualibs/clib/?.so\""		>> ~/.bashrc
RUN echo "DEFAULT_LUA_PATH=`lua -e \"print( package.path)\"`" 	>> ~/.bashrc
RUN echo "DEFAULT_LUA_CPATH=`lua -e \"print( package.cpath)\"`" >> ~/.bashrc
RUN echo "LUA_PATH=\"$SPLAY_PATH;$DEFAULT_LUA_PATH\"" 			>> ~/.bashrc
RUN echo "LUA_CPATH=\"$SPLAY_CPATH;$DEFAULT_LUA_CPATH\""  		>> ~/.bashrc
RUN echo "export LUA_PATH LUA_CPATH"							>> ~/.bashrc
# check
RUN		cat $HOME/.bashrc
# compile splay
RUN cd /splay/src/external_libs/lua-5.1.4/ && make linux
RUN cd /splay/src/daemon/ && make
RUN . ~/.bashrc
RUN /splay/src/install.sh
# expose the port used by the splayd (but since this is a range ...)
EXPOSE 22000
CMD		["echo success", "/splay"]
