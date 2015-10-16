--[[
       Splay ### v1.3 ###
       Copyright 2006-2011
       http://www.splay-project.org
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

-- Splayd settings, can't be changed by Controller
-- Controller will ask for them.
-- Default values are in splayd.lua

--[[ DO YOUR SETTINGS CHANGE HERE ]]--

splayd.settings.key = "KEY" -- received at the registration

splayd.settings.name = "NAME"

splayd.settings.controller.ip = "CONTROLLER"
splayd.settings.controller.port = PORT

-- all sizes are in bytes
splayd.settings.job.max_number = 16
splayd.settings.job.max_mem = 12 * 1024 * 1024 -- 12 Mo
splayd.settings.job.disk.max_size = 1024 * 1024 * 1024 -- 1 Go
splayd.settings.job.disk.max_files = 2048
splayd.settings.job.disk.max_file_descriptors = 128
splayd.settings.job.network.max_send = 10 * 1024 * 1024 * 1024
splayd.settings.job.network.max_receive = 10 * 1024 * 1024 * 1024
splayd.settings.job.network.max_sockets = 128
splayd.settings.job.network.max_ports = 3
splayd.settings.job.network.start_port = 27000
splayd.settings.job.network.end_port = 32000

-- Information about your connection (or your limitations)
-- Enforce them with trickle or other tools
splayd.settings.network.send_speed = 1024 * 1024
splayd.settings.network.receive_speed = 1024 * 1024

--[[ NOTES ABOUT LIMITATIONS

The network.max_send and network.max_receive settings don't directly limit your
bandwith.  They only avoid a job to do something weird. But when a job finish,
it can be quickly replaced by a new one. And each one will have again the same
limitations. So, jobs can use a lot of bandwith if their lifetime is short.

The true way to protect you is using an external bandwith management (QoS) like
'trickle' on unixes that permit you to set limits. Then, put the speed
limitations you have choosed in network.send_speed and network.receive_speed.

CPU limitations are not enforced by splayd, but you can give a low priority to
the process using the 'nice' command.
--]]
