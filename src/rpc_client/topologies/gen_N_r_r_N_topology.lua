howmany=arg[1]
--print("Nodes:", howmany)

output = io.open("large_"..howmany..".xml","w")

print("Writing Modelnet topology. to :","large_"..howmany..".xml" )

output:write("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n")
output:write("<topology>\n")
--write vertices
output:write("\t<vertices>\n")
output:write("\t\t<vertex int_idx=\"0\" role=\"gateway\" int_vn=\"0\" />\n") --hack to start from 1
for i=1,howmany do
		output:write("\t\t<vertex int_idx=\""..i.."\" role=\"virtnode\" int_vn=\""..i.."\" />\n")	
end
--the router nodes in the middle
output:write("\t\t<vertex int_idx=\""..(howmany+1).."\" role=\"gateway\" int_vn=\""..(howmany+1).."\" />\n")
output:write("\t\t<vertex int_idx=\""..(howmany+2).."\" role=\"gateway\" int_vn=\""..(howmany+2).."\" />\n")
output:write("\t</vertices>\n")	
output:write("\t<edges>\n")	
edge_idx=1
--first half of nodes attached to first router
for i=1,howmany/2 do
	output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..i.."\" int_dst=\""..tostring(howmany+1).."\" specs=\"client-stub\"  />\n")	
	edge_idx=edge_idx+1
	output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..tostring(howmany+1).."\" int_dst=\""..i.."\" specs=\"client-stub\"  />\n")	
	edge_idx=edge_idx+1
end
for i=(howmany/2)+1,howmany do
	output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..i.."\" int_dst=\""..tostring(howmany+2).."\" specs=\"client-stub\"  />\n")	
	edge_idx=edge_idx+1
	output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..tostring(howmany+2).."\" int_dst=\""..i.."\" specs=\"client-stub\"  />\n")	
	edge_idx=edge_idx+1
end
--interconnect router r1 and r2
output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..(howmany+1).."\" int_dst=\""..tostring(howmany+2).."\" specs=\"stub-stub\"  />\n")	
edge_idx=edge_idx+1
output:write("\t\t<edge int_idx=\""..edge_idx.."\" int_src=\""..tostring(howmany+2).."\" int_dst=\""..(howmany+1).."\" specs=\"stub-stub\"  />\n")	
edge_idx=edge_idx+1

output:write("\t</edges>\n")
output:write("\t<specs>\n")
output:write("\t\t<client-stub dbl_plr=\"0\" dbl_kbps=\"10240\" int_delayms=\"50\" int_qlen=\"10\" />\n")
output:write("\t\t<stub-stub dbl_plr=\"0\" dbl_kbps=\"1024\" int_delayms=\"10\" int_qlen=\"10\" />\n")
output:write("\t</specs>\n")
output:write("</topology>\n")