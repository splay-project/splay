#!/bin/bash - 
#===============================================================================
#
#          FILE: clone-daemons.sh
# 
#         USAGE: ./clone-daemons.sh
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (RCG), raziel.carvajal@unine.ch
#  ORGANIZATION: 
#       CREATED: 03/30/2016 11:42
#      REVISION:  ---
#===============================================================================

isIpValid ()
{
  ip=$1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    tmp=$ip
    for (( CNTR=0; CNTR<3; CNTR+=1 )); do
      dotIndex=`expr match $tmp '[0-9]*\.'`
      oct=${tmp:0:$(( $dotIndex - 1 ))}
      if  [[ $oct -gt 255 ]]; then
        echo "Octet number $(($CNTR + 1)) is bigger than 255"
        exit 0
      fi
      tmp=${tmp:$dotIndex}
    done
    if  [[ $tmp -gt 255 ]]; then
      echo "Octet number 4 is bigger than 255"
      exit 0
    fi
  else
    echo "Wrong format for an IP address"
    exit 0
  fi
}	# ----------  end of function isIpCorrect  ----------
set -o nounset                              # Treat unset variables as an error
dest=$1
clones=$2
ctrIp=$3
ctrPo=$4
if [[ ! -d $dest ]]; then
  echo "The destination directory doesn't exist"
  exit 0
fi
if [[ $clones != [0-9]* ]]; then
  echo "The number of daemons must be an integer"
  exit 0
fi
isIpValid $ctrIp
if [[ $ctrPo != [0-9]* ]]; then
  echo "Controller port is not an integer"
  exit 0
fi
H=`pwd`
cp src/bash/launch-daemons.sh src/bash/stop-daemons.sh $dest
cd $dest
echo "Copying files to have $clones SplayDaemons..."
for (( CNTR=1; CNTR<=$clones; CNTR+=1 )); do
  daeN="Daemon$CNTR"
  mkdir $daeN
  cp $H/etc/openssl-cert/*.pem $H/src/lua/jobd.lua $H/src/lua/splayd.lua $H/src/lua/settings.lua $H/src/c/jobd $daeN
  echo "splayd.settings.key ='$daeN'" >>$daeN/settings.lua
  echo "splayd.settings.name='$daeN'" >>$daeN/settings.lua
  echo "splayd.settings.controller.port=$ctrPo" >>$daeN/settings.lua
  echo "splayd.settings.controller.ip  ='$ctrIp'" >>$daeN/settings.lua
done
echo "DONE"
