#!/bin/bash

controller="splay2.unineuchatel.ch"
user="unineple_splay"

echo "KILL"

killall splayd
killall jobd
sleep 1
sudo killall -9 splayd

echo "SSLFIX"

if [ ! -e /lib/libssl.so.5 ] ; then
	if [ -e /lib/libssl.so.6 ] ; then
		sudo ln -s /lib/libssl.so.6 /lib/libssl.so.5
	fi
fi

if [ ! -e /lib/libcrypto.so.5 ] ; then
	if [ -e /lib/libcrypto.so.6 ] ; then
		sudo ln -s /lib/libcrypto.so.6 /lib/libcrypto.so.5
	fi
fi

echo "CLEAN"
rm -rf splayd_planetlab/
rm splayd_planetlab.tar.*

echo "SPLAYD"
rd=$RANDOM
wget "http://splay2.unineuchatel.ch/splayd_planetlab.tar.gz?${rd}"
mv splayd_planetlab.tar.gz?${rd} splayd_planetlab.tar.gz
tar xpvf splayd_planetlab.tar.gz
if [[ $? != 0 ]]; then
	sleep 5
	echo "SPLAYD AGAIN"
	rm splayd_planetlab.tar.gz
	wget "http://splay2.unineuchatel.ch/splayd_planetlab.tar.gz?${rd}"
	mv splayd_planetlab.tar.gz?${rd} splayd_planetlab.tar.gz
	tar xpvf splayd_planetlab.tar.gz
fi

hostname=`hostname`
l=${#hostname}

settings=/home/${user}/splayd_planetlab/splayd/settings.lua
sed -i -e "s/KEY/$hostname/" -e "s/NAME/$hostname/" $settings
let "port = 11000 + $RANDOM % 10"
sed -i -e "s/PORT/$port/" -e "s/CONTROLLER/$controller/" $settings
#sed -i s/print/--print/ $settings
#sed -i s/os.exit/--os.exit/ $settings

echo "RUN"
cd /home/${user}/splayd_planetlab
./run.sh

sleep 1

a=`ps aux`

if echo $a | grep "splayd" > /dev/null ; then
	echo "RUNNING"
else
	echo "PROBLEM"
fi

