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


class SplaydController < ApplicationController

	layout 'default'
	before_filter :login_required

	def index
    list
    render :action => 'list'
  end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :destroy, :create, :update ],
         :redirect_to => { :action => :list }

  def list
    #@splayd_pages, @splayds = paginate :splayds, :per_page => 10
		if current_user.admin
			@splayds = Splayd.find(:all,
					:conditions => "status != 'REGISTERED'")
		else
			@splayds = Splayd.find(:all,
					:conditions => "user_id = #{current_user.id} AND status != 'REGISTERED'")
		end
  end

  def show
    @splayd = Splayd.find(params[:id])
  end

  def new
    @splayd = Splayd.new
  end

  def create
		params = {}
		params[:user_id] = current_user.id
		params[:key] = OpenSSL::Digest::MD5.hexdigest(
        rand(1000000000000).to_s + Time.now.to_s)
    @splayd = Splayd.new(params)
    if @splayd.save
      flash[:notice] = 'A new Splayd was successfully created.'
      render :action => 'confirmation'
    else
      render :action => 'new'
    end
  end

	def delete
    @splayd = Splayd.find_by_id(params[:id])
		if @splayd.user.id == current_user.id
			@splayd.status = "DELETED"
			if @splayd.save
				flash[:notice] = 'Splayd was successfully deleted.'
				redirect_to :action => 'list'
			else
				flash[:notice] = 'Problem deleting splayd.'
				redirect_to :action => 'show', :id => @splayd
			end
		else
			flash[:notice] = 'You have not the right to delete this splayd.'
			redirect_to :action => 'list'
		end
	end

#   def edit
#     @splayd = Splayd.find(params[:id])
#   end

#   def update
#     @splayd = Splayd.find(params[:id])
#     if @splayd.update_attributes(params[:splayd])
#       flash[:notice] = 'Splayd was successfully updated.'
#       redirect_to :action => 'show', :id => @splayd
#     else
#       render :action => 'edit'
#     end
#   end

#   def destroy
#     Splayd.find(params[:id]).destroy
#     redirect_to :action => 'list'
#   end

	def self.array_for_map
		splayds = Splayd.find_by_sql(
				"SELECT * FROM splayds WHERE
				latitude IS NOT NULL AND longitude IS NOT NULL AND status != 'REGISTERED' ORDER BY latitude, longitude")

		g_splayds = []
		p_lat, p_lng = nil, nil
		entry = nil
		splayds.each do |splayd|
			if (splayd.latitude != p_lat or splayd.longitude != p_lng)
				p_lat, p_lng = splayd.latitude, splayd.longitude
				# save a previous entry
				if entry
					g_splayds << entry
				end
				# create a new entry
				entry = {}
				entry['latitude'] = splayd.latitude
				entry['longitude'] = splayd.longitude
				entry['status'] = []
				entry['status'] << splayd.status
				entry['ips'] = splayd.ip
			else
				# complete entry
				entry['ips'] = entry['ips'] + ", " + splayd.ip

				found = false
				entry['status'].each do |s|
					if s == splayd.status
						found = true
						break
					end
				end
				if not found
					entry['status'] << splayd.status
					entry['status'][0] = "UNDEF"
				end
			end
		end
		# save last
		if entry
			g_splayds << entry
		end
		return g_splayds
	end

	def self.job_array_for_map(id)
		splayds = Splayd.find_by_sql(["SELECT * FROM splayd_selections, splayds WHERE
				job_id=? AND
				splayd_id=splayds.id AND
				selected='TRUE'
				ORDER BY latitude, longitude", id])

		g_splayds = []
		p_lat, p_lng = nil, nil
		entry = nil
		splayds.each do |splayd|
			if (splayd.latitude != p_lat or splayd.longitude != p_lng)
				p_lat, p_lng = splayd.latitude, splayd.longitude
				# save a previous entry
				if entry
					g_splayds << entry
				end
				# create a new entry
				entry = {}
				entry['latitude'] = splayd.latitude
				entry['longitude'] = splayd.longitude
				entry['status'] = []
				entry['status'] << splayd.status
				entry['ips'] = splayd.ip
			else
				# complete entry
				# TODO je ne comprend pas comment la prochaine ligne a pu bugger vu que
				# entry['ips'] a forcément une ip dedans...
#         entry['ips'] = entry['ips'] + ", " + splayd.ip

#         found = false
#         entry['status'].each do |s|
#           if s == splayd.status
#             found = true
#             break
#           end
#         end
#         if not found
#           entry['status'] << splayd.status
#           entry['status'][0] = "UNDEF"
#         end
			end
		end
		# save last
		if entry
			g_splayds << entry
		end
		return g_splayds
	end
end
