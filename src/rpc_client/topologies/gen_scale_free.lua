--http://en.wikipedia.org/wiki/Barab%C3%A1si%E2%80%93Albert_model#Algorithm

misc=require"splay.misc"

function replace_id(graph, orig, replace)
	--print("SWAP ORIG:", orig, "REPLACE:", replace)	
	--change incoming links: nodes pointing to 'orig' now point to 'replace'
	for k,v in pairs(graph) do
		if v[1]==replace then
			graph[k]={orig}
		end
	end
	
	local tmp_orig_v= misc.dup(graph[orig])
	local tmp_replace_v = misc.dup(graph[replace])
	
	graph[orig]=tmp_replace_v
	graph[replace]=tmp_orig_v
end

--check if routers have a bigger label than the end_nodes
function greater(end_nodes, routers)
	local smaller_router_id=routers[1]
	local bigger_node_id = end_nodes[1]
	--print("smaller router", smaller_router_id, "bigger node", bigger_node_id)
	--the smaller router_id must be bigger than the bigger_node_id
	return smaller_router_id < bigger_node_id
end

math.randomseed(1234)

if #arg<1 then
	print("Usage: lua gen_scale_free.lua nb_nodes <nb_m=1>")
	os.exit()
end
nodes=arg[1]
m=arg[2] or 1



graph={}
list={1,2} --initial list to pick for preferential attachment
graph[1]={2}
graph[2]={1}

--keep track of the nodes degree
degrees={}
for i=1,nodes do
	degrees[i]=1
end
degrees[1]=2
degrees[2]=2

for i=3,tonumber(nodes) do
	graph[i]={}
	for j=1,m do
		local attach_to = list[math.random(#list)]
		table.insert(graph[i],attach_to)
		degrees[i]=degrees[i]+1
		degrees[attach_to]=degrees[attach_to]+1
		table.insert(list,attach_to)
	end
	table.insert(list,i)
	
end

-- MUST REORDER NODE IDS TO have the gateways/transit/stubs with greater IDs than end-nodes (splay limitation)
end_nodes_counter=0
end_nodes={}
routers={}
for k,v in pairs(degrees) do
	--print("node",k,"degree",v)
	if v==2 then 
		table.insert(end_nodes, k)
		end_nodes_counter = end_nodes_counter+1 
	else
		table.insert(routers, k)
	end
end

--print("End-Nodes:", end_nodes_counter, "Router:", nodes-end_nodes_counter)
--print("BEFORE SWAPPING:")
table.sort(end_nodes, function(a,b) return a>b end)
--print("End-Nodes:", table.concat(end_nodes," "))
--table.sort(routers, function(a,b) return a>b end)
--print("Routers:", table.concat(routers ," "))
--for k,v in pairs(graph) do
--	print("Node: "..k, "Degree:"..degrees[k] ,"Neighbor: "..table.concat(v, " "))
--end

while greater(end_nodes, routers) do
	local node_id=end_nodes[1]
	local router_id = routers[1]
	--print("Swapping node_id", node_id, " router_id", router_id)
	replace_id(graph, node_id, router_id)
	end_nodes[1] = router_id
	routers[1] = node_id
	table.sort(end_nodes, function(a,b) return a>b end)
	table.sort(routers)	
end

--print("AFTER SWAPPING:")
table.sort(end_nodes, function(a,b) return a>b end)
print("End-Nodes (tot: "..#end_nodes..")", table.concat(end_nodes," "))
--table.sort(routers, function(a,b) return a>b end)
print("Routers   (tot: "..#routers..")", table.concat(routers ," "))

--for k,v in pairs(graph) do
--	print("Node: "..k, "Degree:"..degrees[k] ,"Neighbor: "..table.concat(v, " "))
--end

-- CSV format for Gephi drawing
print("Writing CSV format to:","random_"..nodes.."nodes_m"..m..".csv" )
output = io.open("random_"..nodes.."nodes_m"..m..".csv","w")
for k,v in pairs(graph) do
	for _,n in pairs(v) do
		output:write(k..";"..n.."\n")	
	end
end

-- GEXF format
print("Writing GEXF format to:","random_"..nodes.."nodes_m"..m..".gexf" )

output = io.open("random_"..nodes.."nodes_m"..m..".gexf","w")
output:write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
output:write("<gexf xmlns=\"http://www.gexf.net/1.2draft\" version=\"1.2\">\n")
output:write("    <meta>\n")
output:write("            <description>"..nodes.." Nodes, M:"..m.."</description>\n")
output:write("    </meta>\n")
output:write("    <graph mode=\"static\" defaultedgetype=\"directed\">\n")
output:write("        <nodes>\n")
for i=1,nodes do
output:write("            <node id=\""..i.."\" label=\""..i.."\" />\n") 
end
output:write("        </nodes>\n")
--            <edge id="0" source="0" target="1" />
output:write("        <edges>\n")
edge_idx=0
for k,v in pairs(graph) do
	for _,n in pairs(v) do
output:write("            <edge id=\""..edge_idx.."\" source=\""..k.."\" target=\""..n.."\" />\n")
		edge_idx=edge_idx+1
	end
end
output:write("        </edges>\n")
output:write("    </graph>\n")
output:write("</gexf>\n")


-- GT-ITM format
print("Writing ModelNet GT-ITM format to:","random_"..nodes.."nodes_m"..m..".xml" )
output = io.open("random_"..nodes.."nodes_m"..m..".xml","w")
output:write("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n")
output:write("<topology>\n")
--write vertices
output:write("\t<vertices>\n")
	output:write("\t\t<vertex int_idx=\"0\" role=\"gateway\" int_vn=\"0\" />\n")

for i=1,nodes do
	local role="virtnode"
	if i> end_nodes_counter then role="gateway" end
	--if degrees[i]~=2 then role="gateway" end 
	output:write("\t\t<vertex int_idx=\""..i.."\" role=\""..role.."\" int_vn=\""..i.."\" />\n")	
end
output:write("\t</vertices>\n")	
output:write("\t<edges>\n")	
edge_idx=1
for k,v in pairs(graph) do
	for _,n in pairs(v) do
		--output:write(k..";"..n.."\n")	
		local edge_delay=math.random(100,200)/10.0		
		local edge_spec="client-stub"
		if k> end_nodes_counter and n > end_nodes_counter then 
			edge_delay=math.random(300,500)/10.0	
			edge_spec="stub-stub" 
		end
		--if degrees[k]>2 and degrees[n]>2 then edge_spec="stub-stub" end
		
		-- inter router delay is 30 to 50 ms
		-- router to node delay is 10 to 20 ms
		
		
		output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..k.."\" int_dst=\""..n.."\" specs=\""..edge_spec.."\"  int_delayms=\""..(edge_delay).."\" />\n")	
		edge_idx=edge_idx+1
		output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..n.."\" int_dst=\""..k.."\" specs=\""..edge_spec.."\"  int_delayms=\""..(edge_delay).."\" />\n")	
		edge_idx=edge_idx+1
	end
end
output:write("\t</edges>\n")
output:write("\t<specs>\n")
output:write("\t\t<client-stub dbl_plr=\"0\" dbl_kbps=\"10240\" int_delayms=\"50\" int_qlen=\"10\" />\n")
output:write("\t\t<stub-stub dbl_plr=\"0\" dbl_kbps=\"1024\" int_delayms=\"20\" int_qlen=\"10\" />\n")
output:write("\t</specs>\n")
output:write("</topology>\n")
