--[[
       Splay ### v1.5 ###
       Copyright 2006-2011
       http://www.splay-project.org
	   Author: Valerio Schiavoni
]]

--[[
This file is part of Splay.

Splay is free software: you can redistribute it and/or modify 
it under the terms of the GNU General Public License as published 
by the Free Software Foundation, either version 3 of the License, 
or (at your option) any later version.

Splay is distributed in the hope that it will be useful,but 
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Splayd. If not, see <http://www.gnu.org/licenses/>.
]]
local pairs=pairs
local type=type
local print=print
local error=error
local table=table
local log=require"splay.log"
local assert=assert
local tonumber=tonumber
--module("splay.tree")
--THIS IS NOT RELATED TO http://en.wikipedia.org/wiki/Splay_tree 
local _M = {}
_M.l_o = log.new(1, "[splay.tree]")
_M._COPYRIGHT   = "Copyright 2006 - 2013"
_M._DESCRIPTION = "N-Ary Tree object and flow operations used by SplayNet."
_M._VERSION     = 1.0

function _M.new()
	local tree = {}
	tree.nodes= {}
	local root = nil
	tree.size = function()
		local n=0
		for k,_ in pairs(tree.nodes) do			
			n=n+1 
		end	
		return n
	end
	tree.root = function()
		return root
	end 
	--[[
	n_id: the id of the node
	p : reference to the parent node
	plc: capacity (as in flow) of the uplink to the parent node. Useful for MAX_FLOW problems. 
	return: the new node (or the existing one if already present)
	--]]
	tree.addnode = function(n_id, p, plc)
		assert(n_id~=nil,"Node id can't be nil.")
		if tree.nodes[n_id]~=nil then
			if  (tree.nodes[n_id].parent==nil and p==nil) or 
			  	(tree.nodes[n_id].parent.id==p.id) then
				return tree.nodes[n_id]
			else
				error("Node "..n_id.." already exists attached to another parent ")				
			end			
		end
		--l_o:debug("Adding node id="..n_id,"plc=",plc)
		--destination_of_flows keeps track of the destination of the flows through the node
		local node={id=n_id, parent=p, children={}, parent_usage=0,parent_link_capacity=plc, flows={}}
		tree.nodes[n_id]=node
		if p==nil 
			then root=node 
		else
			assert(type(p)=="table")
			p.children[n_id]=node
		end
		return node	
	end
	tree.getnode = function(n_id)
		return tree.nodes[n_id]
	end

	tree.height_node = function(n,temp)
		local temp=temp or 0
		if n.parent~=nil then
			temp=tree.height_node(n.parent,temp+1)
		end
		return temp
	end
	tree.leaves=function()
		local leaves={}
		for k,v in pairs(tree.nodes) do
			local c=0
			for k,_ in pairs(v.children) do
				c=c+1
			end
			if c==0 then leaves[k]=v end
		end
		return leaves
	end
	--INCREMENT each parent_usage from node up to root
	--it exemplify a new stream in progress 
	tree.incrementflowto = function(node,raw_topo)
		if node==nil then error("Nil input node") end
		local current=node
		local root_id=tree.root().id
		local root_node_rtt= raw_topo[root_id][node.id][1]
		while current ~=nil do --up to root
			if current.parent~=nil then 
				current.parent_usage=current.parent_usage+1 
				table.insert(current.flows,{root_id, node.id, root_node_rtt })
			end
			current=current.parent
		end
	end
	--DECREMENT each parent_usage from node up to root
	--it exemplify a new stream in progress
	tree.decrementflowto = function(node,raw_topo)
		if node==nil then error("Nil input node") end
		local root_id=tree.root().id
		local root_node_rtt= raw_topo[root_id][node.id][1]
		local current=node
		while current ~=nil do --up to root
			if current.parent_usage>0 then
				current.parent_usage=current.parent_usage-1
				for k,v in pairs(current.flows) do
					if v[1]==root_id and v[2]==node.id and v[3]==root_node_rtt then
						l_o:debug("[decrementflowto] Removing flow from:", root_id," to:",node.id,"rtt:",root_node_rtt)
						current.flows[k]=nil --remove this flow
						break --remove only one, not all matching the criterias
					end
				end
			end
			current=current.parent
		end
	end
	
	--[[
	Increment the flow by one unit from src to dest. There must be a link between the two.
	]]--
	tree.incrementflowfromto=function(src,dest,flowsrc,flowdest,raw_topology)
	
		local src_dest_rtt=raw_topology[flowsrc][flowdest][1]
		--l_o:debug("[incrementflowfromto] src-dest rtt from raw_topology:", src_dest_rtt)
		if src==nil then error("Nil src node")
		elseif dest==nil then error("Nil dest node") end		
		--TODO simplify  to switch  src/dest if link is in the other direction
		--l_o:debug("[incrementflowfromto]IncrementFlowFromTo","root:"..tree.root().id , src.id,dest.id)
		if src.parent~=nil and src.parent.id==dest.id then
			l_o:debug("src:"..src.id.." parent_usage:", src.parent_usage," increment +1")
			src.parent_usage=src.parent_usage+1			
			table.insert(src.flows,{flowsrc, flowdest, src_dest_rtt })
			
		elseif dest.parent~=nil and dest.parent.id==src.id then
			l_o:debug("dest:"..dest.id.." parent_usage:", dest.parent_usage," increment +1")
			dest.parent_usage=dest.parent_usage+1
			table.insert(dest.flows,{flowsrc, flowdest, src_dest_rtt })
			
		else
			error("Cannot find link between node:"..src.id.." and node:"..dest.id)
		end
	end
	
	--[[
	Decrement the flow by one unit from src to dest. Nodes MUST have a parent-child relation,
	in one of the two possible configurations (src-->dest, dest-->src). 
	]]--
	tree.decrementflowfromto=function(src,dest,flowsrc,flowdest,raw_topology)
		local src_dest_rtt=raw_topology[flowsrc][flowdest][1]
		--l_o:debug("[decrementflowfromto]src-dest rtt from raw_topology:", src_dest_rtt)
	
		if src==nil then error("Nil src node")
		elseif dest==nil then error("Nil src node") end		
		--l_o:debug("[decrementflowfromto] DecrementFlowFromTo",src.id,dest.id)
		--TODO simplify  to switch  src/dest if link is in the other direction
		if src.parent~=nil and src.parent.id==dest.id then
			if src.parent_usage>1 then --prevent negative values
				src.parent_usage=src.parent_usage-1
			end
			for k,v in pairs(src.flows) do
				if v[1]==flowsrc and v[2]==flowdest and v[3]==src_dest_rtt then
					src.flows[k]=nil
					break
				end
			end 	
		elseif dest.parent~=nil and dest.parent.id==src.id then
			if dest.parent_usage>1 then --prevent negative values
				dest.parent_usage=dest.parent_usage-1
			end
			for k,v in pairs(dest.flows) do
				if v[1]==flowsdest and v[2]==flowsrc and v[3]==src_dest_rtt then
					dest.flows[k]=nil
					break
				end
			end 				
		else
			error("Cannot find link between node:"..src.id.." and node:"..dest.id)
		end
	end
	
	--traverse from node up to root and build path
	tree.pathtoroot = function(node)
		local path={}
		local current=node
		while current~=nil do 
			table.insert(path,1,current.id) --insert at the beginning of the list
			current=current.parent
		end
		return path
	end
	tree.maxflowstonode= function(node)
		local flows=0
		local current=node
		while current~=nil do 
			if current.parent_usage>flows then flows=current.parent_usage end
			current=current.parent
		end
		return flows
	end	
	--fair-sharing model: when competing flows are detected, each flow gets allocated
	--an equal amount of bandwidth.  
	tree.maxavailbwto=function(node,args) 
		local current=node
		local maxbw=current.parent_link_capacity --initial value, can only decrement	
		while current~=nil do
			if current.parent_link_capacity==nil then break end --reached the root		
			if current.parent_usage>0 then
				if current.parent_link_capacity/(current.parent_usage)<maxbw then
					local oldmaxbw=maxbw
					maxbw = current.parent_link_capacity/(current.parent_usage)
					l_o:debug("[FAIR-BW] Adjusting BW toward", node.id, "from:", oldmaxbw,"to:", maxbw)					
				end		
			end
			current=current.parent
		end
		return maxbw
	end
	
	--unfair-sharing model: bandwidth per flow allocated according to TCP's RTT flow.
	--Details given in :"Accuracy study and improvement of network simulation in the simgrid framework" , Velho,Legrand.   
	--return the maxbw to allow for transfers between the root of the tree and the 'node' param.
	tree.unfairmaxavailbwto=function(node,args)
		local lid=args.lid
		local topology=args.topology
		assert(topology)
		local tree_root=tree.root().id --this is the node that will allocate the BW	
		local node_flow_rtt =tonumber(topology[tree_root][lid][1]) --the RTT from the root to the node
		
		--l_o:debug("NODE_FLOW_RTT from ",tree_root,"(root) to ",leaf, "ms:", node_flow_rtt)
		--[[
		there are many flows through a given link/pairs of nodes. Due to the bottom-up traversal
		it can happen that the source or the destination of a flow on the path up to the root. 
		For this reason we use the values given in the raw_topology table to access the path-delay/flow-rtt
		topology[source][dest][1]. Each node traversed by a flow is decorated with the the number of
		flows traversing its link up to the parent, as well as the source/dest of such flow. 
		The RTTs of the flows traversing each link determine the allocation of the BW for every flow: this
		function decides the BW to allocate by the root of this tree down to the 'node'. 
		Each node in the emulation does such computation using the same values although in a separate manner. 
		--]] 
		l_o:debug("[UNFAIR-BW] Calculating max BW toward:", node.id)
		local current=node
		local maxbw=current.parent_link_capacity --full capacity, can only decrement	
		while current~=nil do
			if current.parent_link_capacity==nil then break end --reached the root		
			if current.parent_usage>1 then -- shared link, allocate maxBW according to flow's RTT
				l_o:debug("[UNFAIR-BW] Current flows through ", current.id," #", current.parent_usage)				
				local rtt_sum=0
				local rtt_reverse=0
				for k,v in pairs(current.flows) do
					l_o:debug("[UNFAIR-BW] from:", v[1], "to:", v[2], "flow_rtt:", v[3] )
					rtt_reverse=rtt_reverse + 1/tonumber(v[3])
				end
				l_o:debug("[UNFAIR-BW] flows rtt_sum:", rtt_sum, "rtt_reverse:", rtt_reverse)					
				local dest_share_bw=(1/node_flow_rtt)/rtt_reverse
				l_o:debug("[UNFAIR-BW] NODE:",node.id, "dest_share_bw:", dest_share_bw )				
				local new_bw = dest_share_bw*current.parent_link_capacity
				if new_bw < maxbw then
					local oldmaxbw=maxbw
					maxbw=new_bw
					l_o:debug("[UNFAIR-BW] Adjusting BW toward", node.id,"(BW_SHARE: "..dest_share_bw.." % )", "from:", oldmaxbw,"to:", maxbw)						
				end				
			end
			current=current.parent
		end
		return maxbw
	end
	
	--(almost) depth-first visit of the tree
	tree.visit = function(node,func,func_ret)
		for k,v in pairs(node.children) do
			func(v,func_ret)
			tree.visit(v,func,func_ret)
		end
	end
	tree.leavesbelow=function(node)
		local lb={}
		local isleaf = function(n,ris) --inner function given to tree visitor
			local c=0
			for k,v in pairs(n.children) do
				c=c+1
			end
			if c==0 then ris[n.id] = true end
		end
		tree.visit(node,isleaf,lb)
		return lb
	end
	return tree
end

return _M