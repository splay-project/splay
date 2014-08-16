#!/bin/bash
SPLAY_INSTALL_DIR="/usr/lib/splayd"
#SPLAY_INSTALL_DIR="splayd_1.2/"
killall lua

function usage {
  echo "Usage: ./splay-cluster-install.sh machine_id splayds_per_machine splay_ctrl_ip"
  exit 1
}
if [ $# -lt 3 ] ; then
  usage
fi

BASE=$1
SPLAYDS_PER_MACHINE=$2
SPLAY_CTRL_IP=$3

mkdir -p ~/workspace/local_splay_cluster/template/
cd ~/workspace/local_splay_cluster/template/
cp $SPLAY_INSTALL_DIR/jobd.lua .
cp $SPLAY_INSTALL_DIR/jobd .
cp $SPLAY_INSTALL_DIR/splayd.lua .
cp $SPLAY_INSTALL_DIR/splayd .
cp $SPLAY_INSTALL_DIR/settings.lua .
cp $SPLAY_INSTALL_DIR/*pem .

# max_mem INT NOT NULL DEFAULT '536870912',
# disk_max_size INT NOT NULL DEFAULT '67108864',
# disk_max_files INT NOT NULL DEFAULT '512',
# network_max_sockets INT NOT NULL DEFAULT '1024',
# network_nb_ports INT NOT NULL DEFAULT '64',

#tune settings.lua for cluster
sed -i -e s/"splayd.settings.key = \"local\""/"splayd.settings.key = \"host_NODE_NUMBER_GOES_HERE\""/ settings.lua
sed -i -e s/"splayd.settings.name = \"my name\""/"splayd.settings.name = \"host_NODE_NUMBER_GOES_HERE\""/ settings.lua
sed -i -e s/"splayd.settings.controller.ip = \"localhost\""/"splayd.settings.controller.ip = \"SPLAY_CTRL_IP\""/ settings.lua
sed -i -e s/"splayd.settings.job.max_number = 16"/"splayd.settings.job.max_number = 4"/ settings.lua
sed -i -e s/"splayd.settings.job.max_mem = 12 \* 1024 \* 1024 -- 12 Mo"/"splayd.settings.job.max_mem = 1368709120 "/ settings.lua 
sed -i -e s/"splayd.settings.job.disk.max_size = 1024 \* 1024 \* 1024 -- 1 Go"/"splayd.settings.job.max_size = 4 * 1024 * 1024 * 1024 "/ settings.lua
sed -i -e s/"splayd.settings.job.network.max_sockets = 64"/"splayd.settings.job.network.max_sockets = 1024"/ settings.lua
sed -i -e s/"splayd.settings.job.network.max_ports = 2"/"splayd.settings.job.network.max_ports = 64"/ settings.lua
sed -i -e s/"splayd.settings.job.disk.max_file_descriptors = 64"/"splayd.settings.job.disk.max_file_descriptors = 1024"/ settings.lua

sed -i -e s/"splayd.settings.job.network.max_send = 1024 \* 1024 \* 1024"/"splayd.settings.job.network.max_send = 1024 * 1024 * 1024 * 1024 "/ settings.lua
sed -i -e s/"splayd.settings.job.network.max_receive = 1024 \* 1024 \* 1024"/"splayd.settings.job.network.max_receive = 1024 * 1024 * 1024 * 1024 "/ settings.lua


sed -i -e s/print/--print/ settings.lua
sed -i -e s/os.exit/--os.exit/ settings.lua
sed -i -e s/"production = true"/"production = false"/ splayd.lua
#sed -i -e s/"splayd.settings.protocol"/"--splayd.settings.protocol"/ settings.lua
echo "splayd.settings.allow_outrange = true" >> settings.lua

cd ..
for ((i = 1 ; i <=$SPLAYDS_PER_MACHINE; i++ ))
do
  mkdir -p hosts/host_${BASE}_${i}
  cp -r template/* hosts/host_${BASE}_${i}
  sed s/NODE_NUMBER_GOES_HERE/${BASE}_${i}/ template/settings.lua > hosts/host_${BASE}_${i}/settings.lua
  sed -i -e  s/SPLAY_CTRL_IP/${SPLAY_CTRL_IP}/ hosts/host_${BASE}_${i}/settings.lua
done

for((j = 1 ; j <= $SPLAYDS_PER_MACHINE; j++))
do
  startport=$[12000+1000*($j+1)]
  endport=$[$startport+999] #each splayd has 1000 ports in range
  echo $startport $endport
  cd hosts/host_${BASE}_${j}/ 
  #ctrlport=$[10999+$[$BASE % 10]] #first avail is 11000
  ctrlport=$[10999+$[ ( $RANDOM % 10 )  + 1 ]] #first avail is 11000
  echo "Starting splayd host_${BASE}_${j} ${SPLAY_CTRL_IP} $ctrlport $startport $endport"
  lua splayd.lua host_${BASE}_${j} ${SPLAY_CTRL_IP} $ctrlport $startport $endport & 
  cd ../../;
  sleep 0.1
done
