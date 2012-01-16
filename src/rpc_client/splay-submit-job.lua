#!/usr/bin/env lua
--[[
       Splay Client Commands ### v1.4 ###
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

-- JSON-RPC over HTTP client for SPLAY controller -- "SUBMIT JOB" command
-- Created by José Valerio

-- BEGIN LIBRARIES
--for the communication over HTTP
local socket = require"socket"
local http   = require"socket.http"
--for the JSON encoding/decoding
local json   = require"json" or require"lib.json"
--for hashing
sha1_lib = loadfile("./lib/sha1.lua")
sha1_lib()
common_lib = loadfile("./lib/common.lua")
common_lib()
-- END LIBRARIES

-- FUNCTIONS

function add_usage_options()
	table.insert(usage_options, "-c, --churn=CHURN_TRACE_FILE\tcommands the SPLAY controller to follow the trace in CHURN_TRACE_FILE")
	table.insert(usage_options, "-o, --options=OPT1:VAL,OPT2:VAL\tpermits to add constraints to the execution of the job, like maximum number of sockets, maximum storage, etc.")
	table.insert(usage_options, "-n, --nb-splayds=NB_SPLAYDS\tthe job will be performed on NB_SPLAYDS splayds, default is 1")
	table.insert(usage_options, "-N, --name\t\t\tthe program will ask for a short name of the job")
	table.insert(usage_options, "-d, --description\t\tthe program will ask for a description of the job")
	table.insert(usage_options, "-a, --args=\"ARG1 ARG2\"\t\tthe protocol arguments, as given with local runs")
	table.insert(usage_options, "    --absolute-time \t\tthe job will be submitted at [YYYY-MM-DD] HH:MM:SS")
	table.insert(usage_options, "    --relative-time \t\tthe job will be submitted after HH:MM:SS")
	table.insert(usage_options, "    --strict \t\t\tthe job will be submitted now / at the scheduled time or rejected with NO_RESSOURCES message")
	table.insert(usage_options, "    --trace_alt\t\t\tthe churn is managed on the splayd side (alternative way)")
	table.insert(usage_options, "-l  --lib=LIB_FILE\ttdeclares the lib as a dependency of the job, and is followed by the -lv flag for specifying the version")
end

function parse_arguments()
	local i = 1
	while i<=#arg do
		--if argument is "-c"
		if arg[i] == "-c" then
			i = i + 1
			--the churn trace file is the next argument
			churn_trace_filename = arg[i]
		--if argument contains "--churn=" at the beginning
		elseif string.find(arg[i], "^--churn=") then
			--the churn trace file is the other part of the argument
			churn_trace_filename = string.sub(arg[i], 9)
		--if argument is "-o"
		elseif arg[i] == "-o" then
			i = i + 1
			--the string "options" is the next argument
			options_string = arg[i]
		--if argument contains "--options=" at the beginning
		elseif string.find(arg[i], "^--options=") then
			--the string "options" is extracted from the rest of the argument
			options_string = string.sub(arg[i], 11)
		--if argument is "-h" or "--help"
		elseif arg[i] == "--help" or arg[i] == "-h" then
			--prints a short explanation of what the program does
			print_line(QUIET, "send \"SUBMIT JOB\" command to the SPLAY CLI server; submits a job for execution\n")
			--prints the usage
			print_usage()
		--if argument is "-q" or "--quiet"
		elseif arg[i] == "--quiet" or arg[i] == "-q" then
			--the print mode is "quiet"
			print_mode = QUIET
		elseif arg[i] == "--verbose" or arg[i] == "-v" then
			--the print mode is "verbose"
			print_mode = VERBOSE
		--if argument is "-n"
		elseif arg[i] == "-n" then
			i = i + 1
			--the number of splayds is the next argument
			nb_splayds = tonumber(arg[i])
		--if argument contains "--nb_splayds=" at the beginning
		elseif string.find(arg[i], "^--nb-splayds=") then
			--the number of splayds is extracted from the rest of the argument
			nb_splayds = tonumber(string.sub(arg[i], 14))
		--if argument is "-i" or "--cli_server_as_ip_addr"
		elseif arg[i] == "-i" or arg[i] == "--cli_server_as_ip_addr" then
			--Flag cli_server_as_ip_addr is true
			cli_server_as_ip_addr = true
		elseif arg[i] == "-d" or arg[i] == "--description" then
			--Flag ask_for_description is true
			ask_for_description = true
		elseif arg[i] == "-N" or arg[i] == "--name" then
			--Flag ask_for_name is true
			ask_for_name = true
		elseif string.find(arg[i], "^--args=") then
			job_args= string.sub(arg[i], 8)
		elseif 	arg[i] == "-a" then
			i = i + 1
			job_args= arg[i]
		--if argument is "--absolute-time YYYY-MM-DD HH:MM:SS"
		elseif arg[i] == "--absolute-time" then
			-- get the current time
			crt_time = os.time()
			i = i + 1
			sch_year = ""
			sch_month = ""
			sch_day = ""
			if string.len(arg[i]) == 10 then
				-- next argument is YYYY-MM-DD
				sch_year = string.sub(arg[i], 1, 4)
				sch_month = string.sub(arg[i], 6, 7)
				sch_day = string.sub(arg[i], 9, 10)
			else
				-- get current year, month, day
				t = os.date('*t')
				sch_year = t.year
				sch_month = t.month
				sch_day = t.day			
			end     
			-- next argument is HH:MM:SS
			i = i + 1
			sch_hour = string.sub(arg[i], 1, 2)
			sch_min = string.sub(arg[i], 4, 5)
			sch_sec = string.sub(arg[i], 7, 8)
			-- compute scheduled time
			scheduled_at = os.time{year=sch_year, month=sch_month, day=sch_day, hour=sch_hour, min=sch_min, sec=sch_sec}
			-- if YYYY-MM-DD HH:MM:SS is in the past, show a warning message
			if scheduled_at < crt_time then
				print_line(NORMAL, "WARNING: Cannot schedule a job in the past! ")
			end
			-- if YYYY-MM-DD HH:MM:SS is more than 30 days away, show a warning message
			if scheduled_at > (crt_time + 2592000) then
				print_line(NORMAL, "WARNING: Job was scheduled over 30 days from now. ")
			end
		-- if argument is "--relative-time HH:MM:SS"
		elseif arg[i] == "--relative-time" then
			-- get the current time
			crt_time = os.time()
			-- next argument is HH:MM:SS
			i = i + 1
			delay_hour = string.sub(arg[i], 1, 2)
			delay_min = string.sub(arg[i], 4, 5)
			delay_sec = string.sub(arg[i], 7, 8)
			delay_time = (delay_hour * 3600) + (delay_min * 60) + delay_sec
			scheduled_at = crt_time + delay_time
		-- if argument is "--strict"
		elseif arg[i] == "--strict" then
			strict = "TRUE"
		elseif arg[i] == "--trace_alt" then
			trace_alt = "TRUE"
		elseif arg[i] == "--lib" or arg[i] == "-l" then
			i = i + 1
			lib_filename = arg[i]
		elseif arg[i] == "-lv" then
			i = i + 1
			lib_version = arg[i]
		--if code_filename is not yet filled and the argument has not matched any of the other rules
		elseif not code_filename then
			--the code file is the argument
			code_filename = arg[i]
			--if the cli_server_url was filled on the config file
			if cli_server_url_from_conf_file then
				--all the required arguments have been filled
				min_arg_ok = true
			end
		--if cli_server_url is not yet filled
		elseif not cli_server_url then
			--CLI server URL is the argument
			cli_server_url = arg[i]
			--all the required arguments have been filled
			min_arg_ok = true
		end
		i = i + 1
	end
end

function submit_job_extra_checks()
	--if the user asked to input a name
	if ask_for_name then
		--asks for the Name
		print_line(QUIET, "Job name:")
		name = io.read()
	end

	--if the user asked to input a description
	if ask_for_description then
		--asks for the Description
		print_line(QUIET, "Description:")
		description = io.read()
	end

	
	if not churn_trace_filename then
		--if number of splayds is empty or less than 1
		if not nb_splayds or nb_splayds<1 then
			--number of splayds is forced to 1
			nb_splayds = 1
			--prints a message reporting it
			print_line(VERBOSE, "\nThe number of splayds is forced to 1\n")
		end
	end

	-- if not scheduled
	if not scheduled_at then
		scheduled_at = 0
	end

	--contructs options table from the options string
	while options_string do
		local colon_sign = string.find(options_string, ":")
		local comma_sign = string.find(options_string, ",")
		local option_key = string.sub(options_string, 1,colon_sign-1)
		if comma_sign then
			local option_value = string.sub(options_string, colon_sign+1, comma_sign-1)
			options[option_key] = option_value
			options_string = string.sub(options_string, comma_sign+1)
		else
			local option_value = string.sub(options_string, colon_sign+1)
			options[option_key] = option_value
			options_string = nil
		end
	end
end

--function send_submit_job: sends a "SUBMIT JOB" command to the SPLAY RPC server
function send_submit_job(name, description, code_filename, lib_filename, lib_version, nb_splayds, churn_trace_filename, options, job_args, cli_server_url, session_id, scheduled_at, strict, trace_alt)
	--prints the arguments
	print_line(VERBOSE, "NAME              = "..name)
	print_line(VERBOSE, "DESCRIPTION       = "..description)
	print_line(VERBOSE, "CODE_FILE         = "..code_filename)

	--initializes the string that holds the churn trace as empty
	local churn_trace = ""
	--if a churn trace file is given
	if churn_trace_filename then
		--opens the file that contains the churn trace
		local churn_trace_file = io.open(churn_trace_filename)
		--if the file exists
		if churn_trace_file then
			--prints the churn trace filename
			print_line(VERBOSE, "CHURN_TRACE_FILE  = "..churn_trace_filename)
			--flushes the whole file into the string "churn_trace"
			churn_trace = churn_trace_file:read("*a")
			--closes the file
			churn_trace_file:close()
		--if not
		else
			--prints an error message
			error("CHURN_TRACE_FILE does not exist")
			--exists
			os.exit()
		end
		nb_splayds = 0
		print_line(VERBOSE, "NB_SPLAYDS        = (specified in churn trace)")
	else
		print_line(VERBOSE, "NB_SPLAYDS        = "..nb_splayds)
	end

	print_line(VERBOSE, "OPTIONS           = ")
	for i,v in pairs(options) do
		print_line(VERBOSE, "\t"..i.."\t = "..v)
	end
	if job_args then
		print_line(VERBOSE, "JOB_ARGS          = "..job_args)
	end
	print_line(VERBOSE, "SESSION_ID        = "..session_id)
	print_cli_server(4)

	if scheduled_at then
		print_line(VERBOSE, "SCHEDULED_AT	  = "..scheduled_at)
	end

	if strict then
		print_line(VERBOSE, "STRICT MODE   	  = "..strict)
	end

	if trace_alt then
		print_line(VERBOSE, "TRACE ALT MODE	  = "..trace_alt)
	end

	--initializes the string that holds the code as empty
	local code = ""
	--opens the file that contains the code
	local code_file = io.open(code_filename)
	--if the file exists
	if code_file then
		--flushes the whole file into the string "code"
		code = code_file:read("*a")
		--closes the file
		code_file:close()
	--if not
	else
		--prints an error message
		error("ERROR: CODE_FILE does not exist")
		--exists
		os.exit()
	end
	
	-- local lib_code = nil
	-- local lib_hash = nil
	if lib_filename then
		local body = json.encode({
			method = "ctrl_api.test_lib_exists",
			params = {lib_filename, lib_version, session_id}
		})
		local response = http.request(cli_server_url, body)
		if check_response(response) then
			local json_response = json.decode(response)
			if json_response.result.ok == false then
				print(json_response.result.message)
				os.exit()
			end
		else
			os.exit()
		end
	else 
		lib_filename = ""
	end
	--put args in arg{} global table
	args_code="arg={}\narg[0]= '".. code_filename.."'\n"
	if job_args then
		local lua_pos = 1
		--for each arg in the args add an item in the arg table
		for w in string.gmatch(job_args, "%S+") do
			 args_code = args_code.."arg["..lua_pos.."]=\""..w.."\"\n"
		end
		code = args_code..code
	end


	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.submit_job",
		params = {name, description, code, lib_filename, lib_version, nb_splayds, churn_trace, options, session_id, scheduled_at, strict, trace_alt}
	})

	--prints that it is sending the message
	print_line(VERBOSE, "\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)

	--if there is a response
	if check_response(response) then
		local json_response = json.decode(response)
		print_line(NORMAL, "Job Submitted:")
		print_line(NORMAL, "JOB_ID           = "..json_response.result.job_id)
		print_line(VERBOSE, "REF              = "..json_response.result.ref)
		print_line(NORMAL, "")
	end

end

--MAIN FUNCTION:
--initializes the variables
lib_filename = nil
lib_version = nil

code_filename = nil
churn_trace_filename = nil
options_string = nil
options = {}
nb_splayds = nil
description = ""
name = ""
ask_for_description = false
ask_for_name = false
scheduled_at = nil
strict = "FALSE"
trace_alt = "FALSE"
command_name = "splay_submit_job"
other_mandatory_args = "CODE_FILE "

--maximum HTTP payload size is 10MB (overriding the max 2KB set in library socket.lua)
socket.BLOCKSIZE = 10000000

load_config()

add_usage_options()

parse_arguments()

print_line(NORMAL, "")

check_min_arg()

check_cli_server()

check_session_id()

submit_job_extra_checks()

--calls send_submit_job
send_submit_job(name, description, code_filename, lib_filename, lib_version, nb_splayds, churn_trace_filename, options, job_args, cli_server_url, session_id, scheduled_at, strict, trace_alt)
