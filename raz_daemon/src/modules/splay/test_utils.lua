utils=require"splay.utils"
job=utils.generate_job(1, 10, 100, 10, "random")
assert(job.nodes)
assert(job.get_live_nodes)
local the_nodes=job.get_live_nodes()
assert(the_nodes)
for i=1,#job.nodes do
	assert(job.nodes[i]==the_nodes[i])
end
print("TEST_OK")
