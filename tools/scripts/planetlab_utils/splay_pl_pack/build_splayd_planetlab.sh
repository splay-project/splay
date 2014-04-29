#!/usr/bin/env bash
#rev 670 has the complete 'leo/' dir, in case something goes wrong we can recover it

cp ../../../../src/daemon/splayd.lua splayd_planetlab/splayd/
cp ../../../../src/daemon/jobd.lua splayd_planetlab/splayd/
cp ../../../../src/daemon/logd.lua splayd_planetlab/splayd/
cp ../../../../src/daemon/settings_pl.lua splayd_planetlab/splayd/settings.lua

cp ../../../../src/daemon/modules/*.lua splayd_planetlab/splayd/modules/
cp ../../../../src/daemon/modules/splay/*.lua splayd_planetlab/splayd/modules/splay/

##test files do not go into distribution
rm splayd_planetlab/splayd/modules/splay/test-dns.lua
rm splayd_planetlab/splayd/modules/splay/test-misc.lua
rm splayd_planetlab/splayd/modules/splay/test-splay-async-dns.lua
rm splayd_planetlab/splayd/modules/splay/test-benc.lua
rm splayd_planetlab/splayd/modules/splay/test-async_dns.lua
rm splayd_planetlab/splayd/modules/test-json.lua


COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "splayd_planetlab.tar.gz"  --exclude=.svn splayd_planetlab/

echo "Splayd4PL built in splayd_planetlab.tar.gz"
