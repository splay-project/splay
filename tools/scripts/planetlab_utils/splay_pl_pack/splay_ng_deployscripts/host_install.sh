#!/bin/bash

# TODO special ssh config file, removing known_hosts each time to avoid key
# changes.

if [[ $1 == "" ]]; then
	echo "${0} <hostname> [<install type>]"
	exit
fi

h=$1

if [[ $2 == "" ]]; then
	type="standard"
else
	type=$2
fi

if [[ $type != "standard" && $type != "dev" ]]; then
	echo "install type not recognized"
	exit
fi

#url="http://splay3.unineuchatel.ch/files/"
url="http://splay2.unineuchatel.ch/"
script="local_install_ng.sh"

echo "URL = " $url
echo "SCRIPT = " $script 

# $RANDOM to protect against proxy/cache

if [[ $type == "standard" ]]; then
	script_t="local_install_ng.sh?$RANDOM"
	slice="unine_splay_ng"
fi

# if [[ $type == "dev" ]]; then
# 	script_t="local_install_dev.sh?$RANDOM"
# 	slice="unine_splay_dev"
# fi
echo "Install type: ${type} on ${1} (${slice})"

ssh -F my_ssh_config ${slice}@$h "rm -f ${script}; wget ${url}${script_t}; mv ${script_t} ${script}; chmod 755 ${script}; ./${script}"

#ssh -F my_ssh_config unine_splay@$h "killall master; killall splayd; killall jobd; rm -fr /home/unine_splay/leo; echo OK"

#ssh -F my_ssh_config unine_splay@$h "ps aux"

#ssh -F my_ssh_config unine_splay@$h "ps aux | grep splayd | wc -l"
#ssh -F my_ssh_config unine_splay@$h "ps aux | grep splayd"

#ssh -F my_ssh_config unine_splay@$h "ls /home/unine_splay/rclocal"
