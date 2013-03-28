## Splayweb ### v1.0.2 ###
## Copyright 2006-2011
## http://www.splay-project.org
## 
## 
## 
## This file is part of Splayd.
## 
## Splayd is free software: you can redistribute it and/or modify 
## it under the terms of the GNU General Public License as published 
## by the Free Software Foundation, either version 3 of the License, 
## or (at your option) any later version.
## 
## Splayd is distributed in the hope that it will be useful,but 
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
## See the GNU General Public License for more details.
## 
## You should have received a copy of the GNU General Public License
## along with Splayd. If not, see <http://www.gnu.org/licenses/>.


require 'localization'
require 'utils'

class JobController < ApplicationController

  @@hello_world = "-- SPLAYPUB tutorial\n\n-- BASE libraries (threads, events, sockets, ...)\nrequire\"splay.base\"\n\n-- RPC library\nrpc = require\"splay.rpc\"\n\n-- accept incoming RPCs\nrpc.server(job.me.port)\n\nfunction call_me(position)\n  log:print(\"I received an RPC from node \"..position)\nend\n\n-- our main function\nfunction SPLAYschool()\n  -- print bootstrap information about local node\n  log:print(\"I'm \"..job.me.ip..\":\"..job.me.port)\n  log:print(\"My position in the list is: \"..job.position)\n  log:print(\"List type is '\"..job.list_type..\"' with \"..#job.nodes..\" nodes\")\n\n  -- wait for all nodes to be started (conservative)\n  events.sleep(5)\n\n  -- send RPC to random node of the list\n  rpc.call(job.nodes[1], {\"call_me\", job.position})\n\n  -- you can also spawn new threads (here with an anonymous function)\n  events.thread(function() log:print(\"Bye bye\") end)\n\n  -- wait for messages from other nodes\n  events.sleep(5)\n\n  -- explicitly exit the program (necessary to kill RPC server)\n  os.exit()\nend\n\n-- create thread to execute the main function\nevents.thread(SPLAYschool)\n\n-- start the application\nevents.loop()\n\n-- now, you can watch the logs of your job and enjoy ;-)\n-- try this job with multiple splayds and different parameters\n"
  @@xml_topology =<<-eos
  <?xml version="1.0" encoding="ISO-8859-1"?>
  <topology>
  	<vertices>
  		<vertex int_idx="0" role="gateway" int_vn="0" />
  		<vertex int_idx="1" role="virtnode" int_vn="1" />
  		<vertex int_idx="2" role="virtnode" int_vn="2" />
  		<vertex int_idx="3" role="virtnode" int_vn="3" />
  		<vertex int_idx="4" role="virtnode" int_vn="4" />
  		<vertex int_idx="5" role="virtnode" int_vn="5" />
  		<vertex int_idx="6" role="virtnode" int_vn="6" />
  		<vertex int_idx="7" role="virtnode" int_vn="7" />
  		<vertex int_idx="8" role="virtnode" int_vn="8" />
  		<vertex int_idx="9" role="virtnode" int_vn="9" />
  		<vertex int_idx="10" role="virtnode" int_vn="10" />
  		<vertex int_idx="11" role="gateway" int_vn="11" />
  		<vertex int_idx="12" role="gateway" int_vn="12" />
  	</vertices>
  	<edges>
  		<edge int_idx="1" int_src="1" int_dst="11" specs="client-stub"  />
  		<edge int_idx="2" int_src="11" int_dst="1" specs="client-stub"  />
  		<edge int_idx="3" int_src="2" int_dst="11" specs="client-stub"  />
  		<edge int_idx="4" int_src="11" int_dst="2" specs="client-stub"  />
  		<edge int_idx="5" int_src="3" int_dst="11" specs="client-stub"  />
  		<edge int_idx="6" int_src="11" int_dst="3" specs="client-stub"  />
  		<edge int_idx="7" int_src="4" int_dst="11" specs="client-stub"  />
  		<edge int_idx="8" int_src="11" int_dst="4" specs="client-stub"  />
  		<edge int_idx="9" int_src="5" int_dst="11" specs="client-stub"  />
  		<edge int_idx="10" int_src="11" int_dst="5" specs="client-stub"  />
  		<edge int_idx="11" int_src="11" int_dst="12" specs="stub-stub"  />
  		<edge int_idx="12" int_src="12" int_dst="11" specs="stub-stub"  />
  		<edge int_idx="13" int_src="12" int_dst="6" specs="client-stub"  />
  		<edge int_idx="14" int_src="6" int_dst="12" specs="client-stub"  />		
  		<edge int_idx="15" int_src="12" int_dst="7" specs="client-stub"  />
  		<edge int_idx="16" int_src="7" int_dst="12" specs="client-stub"  />
  		<edge int_idx="17" int_src="12" int_dst="8" specs="client-stub"  />
  		<edge int_idx="18" int_src="8" int_dst="12" specs="client-stub"  />
  		<edge int_idx="19" int_src="12" int_dst="9" specs="client-stub"  />
  		<edge int_idx="20" int_src="9" int_dst="12" specs="client-stub"  />
  		<edge int_idx="21" int_src="12" int_dst="10" specs="client-stub"  />
  		<edge int_idx="22" int_src="10" int_dst="12" specs="client-stub"  />
  	</edges>
  	<specs>
  		<client-stub dbl_plr="0" dbl_kbps="10240" int_delayms="0" int_qlen="10" />
  		<stub-stub   dbl_plr="0" dbl_kbps="10240" int_delayms="0" int_qlen="10" />		
  	</specs>
  </topology>
  eos
  
  @@demo1=<<-eos
  PARAMS={}
  PARAMS["STREAM_SIZE"]=20 --in Megabytes
  PARAMS["NB_STREAMS"]=3
  log=require"splay.log"
  dns=require"splay.async_dns"
  dns.l_o.level=5
  socket = require"socket.core"
  ts = require"splay.topo_socket" --MUST BE DONE BEFORE SPLAY.BASE
  ts.l_o.level=5
  tb = require"splay.token_bucket"
  tb.l_o.level = 5
  local ts_settings={}
  ts_settings.CHOPPING=true
  ts_settings.MAX_BLOCK_SIZE=tonumber(PARAMS["TS_BLOCK_SIZE"]) or 8192
  assert(ts.init(ts_settings,job.nodes,job.topology,job.position))
  socket=ts.wrap(socket)
  st = require"splay.tree"
  st.l_o.level =5
  require"splay.base"
  events = require"splay.events"
  log=require"splay.log"
  net=require"splay.net"
  tzero=misc.time()
  function assert_is_node(t)
  	if t.ip==nil then log:error("Missing IP in peer table")
  	elseif t.port == nil then log:error("Missing port in peer table")
  	end
  end
  function print_node(n)
  	assert_is_node(n)
  	return n.ip..":"..n.port
  end
  function same_peer(a,b)
  	return a.ip == b.ip and a.port == b.port
  end
  local function pos(node)
  	for k,v in pairs(job.nodes) do
  		if same_peer(node,v) then
  			return k
  		end
  	end
  end
  function tcp_receive(s)
    local r = s:receive(2048)
    while r do
      r = s:receive(2048)
    end
  end
  net.server(job.me.port, tcp_receive)
  log:print("TCP server started on ", job.me.ip, job.me.port)
  function log_bw(lifetime)
  	events.sleep(lifetime)
  	local ts,tr = socket.stats()
  	local end_time=misc.time()
  	run_duration = end_time - start_time 
  	log:print("Run: ",run_duration,"lifetime:",lifetime)
  	local total_sent_kilobytes= misc.bitcalc(ts).kilobytes
  	local total_recv_kilobytes= misc.bitcalc(tr).kilobytes
  	local upload_Kb_s=total_sent_kilobytes/run_duration
  	local download_Kb_s=total_recv_kilobytes/run_duration
  	log:print("Bandwidth total-sent:",ts, total_sent_kilobytes.."Kb"," total-recv:",tr,total_recv_kilobytes.." Kb",misc.bitcalc(ts).megabytes.." MB")
  	log:print("Bandwidth upload Kb/s: "..upload_Kb_s.." download Kb/s: "..download_Kb_s)	
  	events.sleep(2)
  	events.exit()
  	os.exit()
  end
  prev_ts,prev_tr=nil,nil
  bw_telemetry_period=1
  function bw_telemetry_sent()
  	local ts,tr = socket.stats()
  	if prev_ts==nil then 
  		prev_ts=ts 
  	else
  		local delta=ts-prev_ts
  		local kilobits= misc.bitcalc(delta).kilobits
  		local kilobytes= misc.bitcalc(delta).kilobytes
  		local megabits=misc.bitcalc(delta).megabits
  		log:print("node-pos:",job.position,misc.time()-tzero,"telemetry-bw-sent",ts,"Kbps: "..kilobits,"KBps: "..kilobytes,"Mbps: "..megabits)
  		prev_ts=ts
  	end
  end
  function tcp_upload(s)
  	local t0=misc.time()
  	s:send(msg)
  	local t = misc.time()-t0
  	local bits=misc.bitcalc(#msg)
  	log:print(misc.time()-tzero,"Transfer time:", t,"throughput (upload):", (bits.kilobytes)/t," KB/s", (bits.kilobits)/t," Kb/s" )		
  end
  function uploader(wait_before_start,dest,msg)
  	events.sleep(wait_before_start)
  	log:print("Starting new upload to ", print_node(dest))
  	local t0=misc.time()	
  	net.client(dest,{send=tcp_upload})
  end
  --BEGIN DCM PROTOCOL --
  net=require"splay.net"
  function handle_dcm(msg, ip, port) --the ip and port the data was sent from.
  	--log:print(job.position,"RECEIVE DCM EVENT:",msg)
  	local msg_tokens=misc.split(msg, " ")
  	ts.handle_tree_change_event(msg_tokens)	
  end
  dcm_udp_port=job.me.port+1 --by convention, +1 is the udp_port for topology
  u = net.udp_helper(dcm_udp_port, handle_dcm)
  last_proposed=nil
  last_ev_broadcasted_idx=0
  function dcm()
  	--log:debug("dcm",ts.last_event_idx, last_ev_broadcasted_idx)
  	if ts.last_event_idx>last_ev_broadcasted_idx then
  		for i=last_ev_broadcasted_idx+1, ts.last_event_idx do
  			local e=ts.tree_events[i]
  			if e==nil then break end			
  			last_ev_broadcasted_idx = i 		
  			--log:print(job.position, i, "SEND DCM EVENT:", e)
  			for k,dest in pairs(job.nodes) do --should use UDP multicast,with many nodes this could be slow
  				if not  (dest.ip == job.me.ip and dest.port ==job.me.port) then
  					u.s:sendto(e, dest.ip, dest.port+1)
  				end
  			end
  		end
  	end	
  end
  --END DCM PROTOCOL --
  events.run(function()
  	events.periodic(0.50, dcm)
    events.thread(function() log_bw(60) end)
  	start_time=misc.time()
  	local nb_streams=tonumber(PARAMS["NB_STREAMS"]) or 1
  	if job.position<=nb_streams then
  		local size=1024*1024*(tonumber(PARAMS["STREAM_SIZE"]) or 70) -- 0 megabytes
  		log:print("Message size MB:",misc.bitcalc(size).megabytes, "KB:", misc.bitcalc(size).kilobytes, "Kb:",misc.bitcalc(size).kilobits )
  		msg=misc.gen_string(size)	
  		events.periodic(bw_telemetry_sent,bw_telemetry_period)			
  		uploader(job.position*5, job.nodes[job.position+5],msg)
  	end
  end)
  
  eos
  
  @@topology_drawing="demo1.jpg"
  
	layout 'default'
	before_filter :login_required

  def index
    list
    render :action => 'list'
  end

	# ajax
	def long_lat
		l = Localization.new(request.env['REMOTE_ADDR'])
#     render :text => request.env
		render :text => "#{l.latitude}|#{l.longitude}"
	end

	# ajax test
	def ajax
		render :text => 'ajax'
	end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :destroy, :create, :update ],
         :redirect_to => { :action => :list }

  def list
		#@job_pages, @jobs = paginate :jobs, :per_page => 20
		if current_user.admin == 1
			@jobs = Job.find(:all)
		else
			@jobs = Job.find(:all, :conditions => "user_id = #{current_user.id}")
		end
  end

  def show
		# TODO check that the user is authorized to see this job
		@g_splayds = SplaydController::job_array_for_map(params[:id])
    @job = Job.find(params[:id])
  end

  def new_from_job
    @job = Job.find_by_id(params[:id])
		render :action => 'new'
  end

  def new_from_file
  end

  def new
		# for map
		@g_splayds = SplaydController::array_for_map

		if params[:job] # new job from file
      lines  = if params[:job][:code].respond_to?(:rewind)
        params[:job][:code].rewind
        params[:job][:code].read
      else
        params[:job][:code]
      end 
      lines = lines.split("\n")

      options = parse_ressources(lines)
      options[:code] = clean_source(lines).join("\n")

			@job = Job.new(options)
		elsif params[:clone_id] 
			@job = Job.find_by_id(params[:clone_id])
		else
      options = {}
		  if current_user.demo == 1
		    options[:max_time] =  300
      end
			@job = Job.new(options)
      @job.code = @@demo1
      @job.topology = @@xml_topology
		end
  end

  def kill
		@job = Job.find_by_id(params[:id])
		@job.command = 'KILL'
    if @job.save
      flash[:notice] = 'Job was killed.'
    else
      flash[:notice] = 'Problem killing job.'
    end
    redirect_to :action => 'list'
	end

  def create

		# Temporary limitations for non admin users.
		if current_user.demo == 1
			if params[:job][:nb_splayds].to_i > 100
				params[:job][:nb_splayds] = 100
			end
			if params[:job][:max_time].to_i > 300
				params[:job][:max_time] = 300
			end
			params[:job][:code] = @@hello_world
		end

		@g_splayds = SplaydController::array_for_map

		if params[:job][:localization] == ""
			params[:job][:localization] = nil
		end

		if params[:job][:latitude] == ""
			params[:job][:latitude] = nil
		end

		if params[:job][:longitude] == ""
			params[:job][:longitude] = nil
		end

		if params[:job][:distance] == ""
			params[:job][:distance] = nil
		end
		
		# No hostmask ATM
		params[:job][:hostmasks] = nil
		params[:job][:script] = ""

		# No geolocalization ATM
#     params[:job][:longitude] = nil
#     params[:job][:latitude] = nil
#     params[:job][:distance] = nil

		# TODO check that at least one splayd of this user runs before accepting the job.

		params[:job][:user_id] = current_user.id
		params[:job][:ref] = OpenSSL::Digest::MD5.hexdigest(
        rand(1000000000000).to_s + Time.now.to_s)
		params[:job][:status_time] = Time.now.to_i
      
		if current_user.demo == 0 and params[:job][:trace]
      trace = if params[:job][:trace].respond_to?(:rewind)
        params[:job][:trace].rewind
        params[:job][:trace].read
      else
        params[:job][:trace]
      end 
      if trace.split("\n").size > 0
        params[:job][:nb_splayds] = trace.split("\n").size
        params[:job][:scheduler] = 'trace'
        params[:job][:scheduler_description] = trace
        params[:job][:die_free] = 'FALSE'
      end
    end
    params[:job].delete('trace') 

    @job = Job.new(params[:job])
    if @job.save
      flash[:notice] = 'Job was successfully created.'
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

	def map
		@g_splayds = SplaydController::job_array_for_map(params[:id])
	end
#   def edit
#     @job = Job.find(params[:id])
#   end

#   def update
#     @job = Job.find(params[:id])
#     if @job.update_attributes(params[:job])
#       flash[:notice] = 'Job was successfully updated.'
#       redirect_to :action => 'show', :id => @job
#     else
#       render :action => 'edit'
#     end
#   end

#   def destroy
#     Job.find(params[:id]).destroy
#     redirect_to :action => 'list'
#   end
end
