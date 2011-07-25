#!/bin/bash

./build_splayd_planetlab.sh
scp splayd_planetlab.tar.gz root@splay2.unineuchatel.ch:/home/splay/splayweb_1.0.2/public
scp local_install.sh root@splay2.unineuchatel.ch:/home/splay/splayweb_1.0.2/public
#./install.sh ../unineple_splay_nodes.txt
