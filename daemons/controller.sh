#!/bin/sh

#killall /usr/bin/ruby
#sleep 1
#killall -9 /usr/bin/ruby

./init.rb

./logd.rb 11100 &
./logd.rb 11101 &
./logd.rb 11102 &
./logd.rb 11103 &
./logd.rb 11104 &
./logd.rb 11105 &
./logd.rb 11106 &
./logd.rb 11107 &
./logd.rb 11108 &
./logd.rb 11109 &

./splayd.rb 11000 &
./splayd.rb 11001 &
./splayd.rb 11002 &
./splayd.rb 11003 &
./splayd.rb 11004 &
./splayd.rb 11005 &
./splayd.rb 11006 &
./splayd.rb 11007 &
./splayd.rb 11008 &
./splayd.rb 11009 &

./jobd_standard.rb &
./jobd_trace.rb &
./unseend.rb &
./loadavgd.rb &
./statusd.rb &
./blacklistd.rb &

