#!/bin/bash
#TODO check that this machine can build .deb archives,
#it must be a debian-based distro. Check also that 
#it matches the given arch. 

ver=$1
if [[ $ver == "" ]]; then
	echo "Usage: build_debs.sh VER ARCH [i386(default),amd64]"
	exit
fi
arch=$2
if [[ $arch == "" ]]; then
	arch="i386"
fi

cd deb/
./makedeb_daemon.sh ${ver} ${arch}
