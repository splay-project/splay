for i in 1 5 10 50 100 500
do
	echo "Creating $i B random files..."
	lua gen_random_file.lua rand $i B &
	lua gen_random_file.lua rand_text $i B &
	lua gen_random_file.lua rand_non_zero $i B &
	wait
	echo "Creating $i kB random files..."
	lua gen_random_file.lua rand $i kB &
	lua gen_random_file.lua rand_text $i kB &
	lua gen_random_file.lua rand_non_zero $i kB &
	wait
	echo "Creating $i MB random files..."
	lua gen_random_file.lua rand $i MB &
	lua gen_random_file.lua rand_text $i MB &
	lua gen_random_file.lua rand_non_zero $i MB &
	wait
done
