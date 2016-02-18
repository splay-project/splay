require 'splay.base'

function main()
  while events.yield() do
    events.sleep(0.5)
    log:print('PeerPosition: '..job.position)
  end
end

events.thread(main)
events.loop()
