#!/bin/bash

./build_splayd_planetlab.sh
scp splayd_planetlab.tar.gz splay2.unineuchatel.ch:/splay/splayweb/public/
scp local_install.sh splay2.unineuchatel.ch:/splay/splayweb/public/
./install.sh ../unineple_splay_nodes.txt