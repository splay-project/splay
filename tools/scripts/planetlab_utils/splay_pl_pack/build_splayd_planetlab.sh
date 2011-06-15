#!/usr/bin/env bash
#rev 670 has the complete 'leo/' dir, in case something goes wrong we can recover it

#cp ../../../../src/daemon/*.lua splayd_planetlab/splayd/
cp ../../../../src/daemon/modules/*.lua splayd_planetlab/splayd/modules/
cp ../../../../src/daemon/modules/splay/*.lua splayd_planetlab/splayd/modules/splay/

COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "splayd_planetlab.tar.gz"  --exclude=.svn splayd_planetlab/

echo "Splayd4PL built in splayd_planetlab.tar.gz"
