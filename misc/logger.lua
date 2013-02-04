local misc = require"splay.misc"

_LOGMODE = "file"
_LOGFILE = os.getenv("HOME").."/Desktop/logfusesplay/log.txt"
_TIMESTAMP = true
local log_tbl = {}
log_domains = {}


--LOGGING FUNCTIONS

local write_log_line, write_last_log_line

--if we are just printing in screen
if _LOGMODE == "print" then
	write_log_line = print
	write_last_log_line = print
--if we print to a file
elseif _LOGMODE == "file" then
	write_log_line = function(message, ...)
		local logfile1 = io.open(_LOGFILE,"a")
		logfile1:write(message)
		for i=1,arg["n"] do
			logfile1:write("\t"..tostring(arg[i]))
		end
		logfile1:write("\n")
		logfile1:close()
	end
	write_last_log_line = write_log_line
--if we want to print to a file efficiently
elseif _LOGMODE == "file_efficient" then
	--write_log_line adds an entry to the logging table
	write_log_line = function(message, ...)
		table.insert(log_tbl, message)
		for i=1,arg["n"] do
			table.insert(log_tbl, "\t"..tostring(arg[i]))
		end
		table.insert(log_tbl, "\n")
	end
	--write_last_log_line writes the table.concat of all the log lines in a file and cleans the logging table
	write_last_log_line = function(message, ...)
		local logfile1 = io.open(_LOGFILE,"a")
		write_log_line(message, ...)
		logfile1:write(table.concat(log_tbl))
		logfile1:close()
		log_tbl = {}
	end
else
	--empty functions
	write_log_line = function(message, ...) end
	write_last_log_line = function(message, ...) end
end

--function logprint: function created to send log messages; it handles different log domains, like DB_OP (Database Operation), etc.
function logprint(log_domain, message, ...)
	--if logging in the proposed log domain is ON
	if log_domains[log_domain] then
		if _TIMESTAMP then
			message = tostring(misc.time())..": "..(message or "")
		end
		write_log_line(message, ...)
	end
end

function last_logprint(log_domain, message, ...)
	--if logging in the proposed log domain is ON
	if log_domains[log_domain] then
		if _TIMESTAMP then
			message = tostring(misc.time())..": "..(message or "")
		end
		--writes a log line with the message
		write_last_log_line(message, ...)
	end
end

function tbl2str(name, order, input_table)
	--if input_table is a string, concatenate the value between quotes
	if type(input_table) == "string" then
		return name.."=\""..input_table.."\""
	elseif type(input_table) == "number" or type(input_table) == "boolean" or type(input_table) == "nil" then
		return name.."="..tostring(input_table)
	end
	--creates a table to store all strings; more efficient to do a final table.concat than to concatenate all the way
	local output_tbl = {"table: "..name.."\n"}
	--indentation is a series of n x "\t" (tab characters), where n = order
	local indentation = string.rep("\t", order)
	--for all elements of the table
	for i,v in pairs(input_table) do
		--the start of the line is the indentation + table_indx
		table.insert(output_tbl, indentation..tbl2str(i, order+1, v).."\n")
	end
	--returns the concatenation of all lines
	return table.concat(output_tbl)
end