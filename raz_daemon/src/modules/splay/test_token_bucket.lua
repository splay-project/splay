
require"splay.base"
tb=require"splay.token_bucket"

events.run(function()
	bucket=assert(tb.new({tokens=2000,capacity=2000,fill_rate=512}))
	log:print("tokens",bucket.get_tokens())
	log:print("consume(512)",bucket:consume(512))
	log:print("consume(512)",bucket:consume(512))
	events.sleep(1)
	log:print(bucket.timestamp)
	log:print("tokens",bucket:get_tokens())
	events.sleep(1)
	log:print(bucket.timestamp)
	log:print("tokens",bucket:get_tokens())
	log:print("consume(2048)",bucket:consume(2048))
	events.sleep(1)
	log:print("consume(1024)",bucket:consume(1024))
	for i=1,10 do
		events.sleep(0.5)
		log:print("consume(1024)",bucket:consume(1024))
		log:print("tokens",bucket:get_tokens())
		log:print(bucket.timestamp)
	end
	
end)