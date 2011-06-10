#!/usr/bin/env bash
#rev 670 has the complete 'leo/' dir, in case something goes wrong we can recover it
#TODO: the build script should use the splayd sources from ../../../../src/deamon instead of having a copy of them
# so that we always ship the latest version in splayd_planetlab

#cp ../../../../src/daemon/*.lua splayd_planetlab/splayd/
cp ../../../../src/daemon/modules/*.lua splayd_planetlab/splayd/modules/
cp ../../../../src/daemon/modules/splay/*.lua splayd_planetlab/splayd/modules/splay/

COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "splayd_planetlab.tar.gz"  --exclude=.svn splayd_planetlab/

echo "Splayd4PL built in splayd_planetlab.tar.gz"
