all:
	tt churn_lang.tt

clean:
	rm -f churn_lang.rb exemple.out

test: all
	ruby churn_gen.rb -i example.churn -o example.out -w

help:
	@@echo "To use the churn generator you need ruby and"
	@@echo "treetop: sudo gem install treetop"
