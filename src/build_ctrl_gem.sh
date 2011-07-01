#!/bin/bash
ver=$1
if [[ $ver == "" ]]; then
	echo "Usage: build_ctrl_gem.sh VER"
	exit
fi

cd controller/

cp splay-controller-template.gemspec splay-controller-${ver}.gemspec
sed -i "" s/"##VERSION##"/${ver}/g splay-controller-${ver}.gemspec

gem build splay-controller-${ver}.gemspec
rm splay-controller-${ver}.gemspec
cd ..
mv controller/splay-controller-${ver}.gem .