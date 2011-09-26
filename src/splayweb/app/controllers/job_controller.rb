## Splayweb ### v1.1 ###
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

  @@hello_world = "-- SPLAYschool tutorial\n\n-- BASE libraries (threads, events, sockets, ...)\nrequire\"splay.base\"\n\n-- RPC library\nrpc = require\"splay.rpc\"\n\n-- accept incoming RPCs\nrpc.server(job.me.port)\n\nfunction call_me(position)\n  log:print(\"I received an RPC from node \"..position)\nend\n\n-- our main function\nfunction SPLAYschool()\n  -- print bootstrap information about local node\n  log:print(\"I'm \"..job.me.ip..\":\"..job.me.port)\n  log:print(\"My position in the list is: \"..job.position)\n  log:print(\"List type is '\"..job.list_type..\"' with \"..#job.nodes..\" nodes\")\n\n  -- wait for all nodes to be started (conservative)\n  events.sleep(5)\n\n  -- send RPC to random node of the list\n  rpc.call(job.nodes[1], {\"call_me\", job.position})\n\n  -- you can also spawn new threads (here with an anonymous function)\n  events.thread(function() log:print(\"Bye bye\") end)\n\n  -- wait for messages from other nodes\n  events.sleep(5)\n\n  -- explicitly exit the program (necessary to kill RPC server)\n  os.exit()\nend\n\n-- create thread to execute the main function\nevents.thread(SPLAYschool)\n\n-- start the application\nevents.loop()\n\n-- now, you can watch the logs of your job and enjoy ;-)\n-- try this job with multiple splayds and different parameters\n"

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
      @job.code = @@hello_world
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

                # Avoid converting time to UTC in the database
		sch_time = Time.parse(params[:job][:scheduled_at])
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
