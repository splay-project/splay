def prefix(job)
	t = Time.now
  pfix = "#{t.strftime("%H:%M:%S")}.#{t.usec} " <<  "job_ref "            
	return pfix
end

puts prefix("job") << "some_msg"

t= Time.at(1377782211)
puts "#{t.strftime("%H:%M:%S")}.439779"