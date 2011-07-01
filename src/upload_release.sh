#!/bin/bash
ver=$1
if [[ $ver == "" ]]; then
	echo "Usage: upload_release.sh VERSION FTP_USER FTP_PASSWD"
	exit
fi

ftp_user=$2
if [[ $ftp_user == "" ]]; then
	echo "Usage: upload_release.sh VERSION FTP_USER FTP_PASSWD"
	exit
fi

ftp_passwd=$3
if [[ $ftp_passwd == "" ]]; then
	echo "Usage: upload_release.sh VERSION FTP_USER FTP_PASSWD"
	exit
fi

daemon=splayd_${ver}.tar.gz
controller=controller_${ver}.tar.gz
luarocks=splayd_${ver}.rockspec
osx_pkg=splayd_${ver}.pkg

ftp -u ftp://${ftp_user}:${ftp_passwd}@splay-project.org/sites/splay-project.org/files/release/ ${daemon} ${controller}
#ftp -u ftp://${ftp_user}:${ftp_passwd}@splay-project.org/sites/splay-project.org/files/binaries/ ${luarocks} ${osx_pkg}