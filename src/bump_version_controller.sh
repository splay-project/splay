#!/bin/bash
if [[ $1 == "" ]]; then
	echo "Usage: ./bump_version_controller.sh NEW_VERSION"
	exit
fi
##the difference between linux-gnu and darwing is in the suffix given to sed
if [[ "$OSTYPE" == 'linux-gnu' ]]; then
   	find daemon -name "*.rb" | xargs  sed -i"" s/'Splay Client Commands ### v..* ###'/"Splay Client Commands ### v${new_version} ###"/ 
elif [[ "$OSTYPE" == 'darwin10.0' ]]; then
   	find daemon -name "*.rb" | xargs  sed -i "" s/'Splay Client Commands ### v..* ###'/"Splay Client Commands ### v${new_version} ###"/ 
fi
