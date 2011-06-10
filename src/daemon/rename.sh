#!/bin/bash
nameOfThisSplayd=$(hostname);
#make a backup of settings.lua to settings.luae
sed -i.backup -e "s/\"my name\"/\"${nameOfThisSplayd}\"/g" settings.lua;
# delete the last 2 lines of settings.lua
sed -i.backup '$d' settings.lua;
sed -i.backup '$d' settings.lua;
sed -i.backup '$d' settings.lua;
