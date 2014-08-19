if #arg<1 then
	print("Usage: lua gen_star_topology.lua nb_nodes")
	os.exit()
end

howmany=arg[1]
--print("Nodes:", howmany)

output = io.open("star_"..howmany..".xml","w")

print("Writing Modelnet topology. to :","star_"..howmany..".xml" )

output:write("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n")
output:write("<topology>\n")
--write vertices
output:write("\t<vertices>\n")
for i=1,howmany do
		output:write("\t\t<vertex int_idx=\""..i.."\" role=\"virtnode\" int_vn=\""..i.."\" />\n")	
end
--the router node in the middle
output:write("\t\t<vertex int_idx=\""..tostring(howmany+1).."\" role=\"gateway\" int_vn=\""..tostring(howmany+1).."\" />\n")	
output:write("\t</vertices>\n")	
output:write("\t<edges>\n")	
edge_idx=1
for i=1,howmany do
	
	output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..i.."\" int_dst=\""..tostring(howmany+1).."\" specs=\"client-stub\"  />\n")	
	edge_idx=edge_idx+1
	output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..tostring(howmany+1).."\" int_dst=\""..i.."\" specs=\"client-stub\"  />\n")	
	edge_idx=edge_idx+1
	
end
output:write("\t</edges>\n")
output:write("\t<specs>\n")
output:write("\t\t<client-stub dbl_plr=\"0\" dbl_kbps=\"1024\" int_delayms=\"50\" int_qlen=\"10\" />\n")
output:write("\t</specs>\n")
output:write("</topology>\n")
