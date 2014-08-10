s="1377877544.5136"
t=s.split(".")
jt=Time.at(t[0].to_i,t[1].to_i)
puts "Localtime: " << jt.strftime("%H:%M:%S") << "." <<jt.usec.to_s

puts(Time.at(s.to_f).strftime("%H:%M:%S"))

t0 = Time.now
puts "bla bla"
t = (Time.now - t0)
puts ("Time taken: #{t.to_f}")

#I, [17:56:53 #18129]  INFO -- : JOBD at 10.0.0.10:39004 localtime: 17:56:32.497854 DIFF: 20.910511 RTT: 0.0005455
#I, [17:56:53 #18128]  INFO -- : JOBD at 10.0.0.8:46770 localtime: 17:56:55.464413 DIFF: -2.021492 RTT: 0.0008295
#I, [17:56:53 #18122]  INFO -- : JOBD at 10.0.0.9:43470 localtime: 17:57:30.945041 DIFF: -37.189341 RTT: 0.0010255
#I, [17:56:53 #18122]  INFO -- : JOBD at 10.0.0.13:47041 localtime: 17:57:07.964511 DIFF: -14.096689 RTT: 0.000689
#I, [17:56:53 #18126]  INFO -- : JOBD at 10.0.0.12:44367 localtime: 17:57:01.933347 DIFF: -7.949404 RTT: 0.001067