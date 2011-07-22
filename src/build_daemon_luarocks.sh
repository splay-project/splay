#!/bin/bash
ver=$1
if [[ ${ver} == "" ]]; then
	echo "Usage: build_deamon_luarocks.sh VER"
	exit
fi

cp splayd_template.rockspec splayd-${ver}-0.rockspec
#note to myself: inplace replacement might still fail 
#"VER" can contain characters special to sed's replacement part
sed -i "" s/"##VERSION##"/${ver}-0/ splayd-${ver}-0.rockspec
sed -i "" s/"##VERSION_URL##"/${ver}/ splayd-${ver}-0.rockspec
