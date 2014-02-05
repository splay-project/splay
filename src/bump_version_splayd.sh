#!/bin/bash
if [[ $1 == "" ]]; then
	echo "Usage: ./bump_version_splayd.sh NEW_VERSION"
	exit
fi
new_version=$1
##the difference between linux-gnu and darwing is in the suffix given to sed
if [[ "$OSTYPE" == 'linux-gnu' ]]; then
   	find daemon -name "*.lua" | xargs  sed -i"" s/'Splay ### v..* ###'/"Splay ### v${new_version} ###"/ 
	find daemon -name "*.c" | xargs  sed -i"" s/'Splay ### v..* ###'/"Splay ### v${new_version} ###"/ 
   	find daemon -name "*.h" | xargs  sed -i"" s/'Splay ### v..* ###'/"Splay ### v${new_version} ###"/   	
elif [[ "$OSTYPE" == 'darwin10.0' ]]; then
   	find daemon -name "*.lua" | xargs  sed -i "" s/'Splay ### v..* ###'/"Splay ### v${new_version} ###"/ 
   	find daemon -name "*.c" | xargs  sed -i "" s/'Splay ### v..* ###'/"Splay ### v${new_version} ###"/ 
   	find daemon -name "*.h" | xargs  sed -i "" s/'Splay ### v..* ###'/"Splay ### v${new_version} ###"/
fi
