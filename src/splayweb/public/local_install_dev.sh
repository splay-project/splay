#!/bin/bash

controller="splay3.unineuchatel.ch"
user="unine_splay_dev"

echo "PACKAGES"

#sudo yum install hg
#sudo yum install vim-enhanced

sudo yum install openssl
#sudo yum install readline

#sudo yum install openssl-devel
#sudo yum install gcc
#sudo yum install make
#sudo yum install readline-devel
#sudo yum install unzip

echo "KILL"

killall master
killall splayd
killall jobd
sleep 1
sudo killall -9 master
sudo killall -9 splayd
sudo killall -9 jobd

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

rm install.sh
sudo rm -fr leo
rm netslave_planetlab.tar.* master_planetlab.tar.* splayd_planetlab.tar.*

echo "SPLAYD"
rd=$RANDOM
#wget "http://splay3.unineuchatel.ch/files/splayd_planetlab.tar.gz?${rd}"
wget "http://splay2.unineuchatel.ch/splayd_planetlab.tar.gz?${rd}"
mv splayd_planetlab.tar.gz?${rd} splayd_planetlab.tar.gz
tar xpvf splayd_planetlab.tar.gz
if [[ $? != 0 ]]; then
	sleep 5
	echo "SPLAYD AGAIN"
	rm splayd_planetlab.tar.gz
	#wget "http://splay3.unineuchatel.ch/files/splayd_planetlab.tar.gz?${rd}"
	wget "http://splay2.unineuchatel.ch/splayd_planetlab.tar.gz?${rd}"
	mv splayd_planetlab.tar.gz?${rd} splayd_planetlab.tar.gz
	tar xpvf splayd_planetlab.tar.gz
fi

hostname=`hostname`
l=${#hostname}

settings=/home/${user}/leo/splayd/settings.lua
sed -i -e "s/KEY/$hostname/" -e "s/NAME/$hostname/" $settings
let "port = 11000 + $RANDOM % 10"
sed -i -e "s/PORT/$port/" -e "s/CONTROLLER/$controller/" $settings

echo "BOOT"

#if ! grep "run.sh" /etc/rc.local > /dev/null ; then
echo "echo '#!/bin/sh' > /etc/rc.local" > local
echo "echo 'touch /var/lock/subsys/local' >> /etc/rc.local" >> local
echo "echo 'sudo -u ${user} /home/${user}/leo/run.sh'  >> /etc/rc.local" >> local
sudo bash local
rm local
#fi

echo "RUN"
cd /home/${user}/leo
./run.sh

sleep 1

a=`ps aux`

if echo $a | grep "splayd" > /dev/null ; then
	echo "RUNNING"
else
	echo "PROBLEM"
fi

