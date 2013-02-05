local misc = require"splay.misc"

local logfile, logrules, logbatching, global_details, global_timestamp, global_elapsed


--LOGGING FUNCTIONS

--default: write_log is an empty function (no logging)
local write_log = function() end

--function string_deconcat: generates a table out of a string containing a list of words separated by spaces
local function string_deconcat(str1)
	--if str1 is nil, returns nil
	if not str1 then
		return nil
	end
	--initializes tbl1 as an empty table
	local tbl1 = {}
	--for each word in str1
	for word in str1:gmatch("[^%s]+") do
		--inserts the word into the table
		table.insert(tbl1, word)
	end
	--returns the table
	return tbl1
end

--function generate_tag_string: creates a string with all the tags using the format "[TAG1] [TAG2] ...", takes a table as input
local function generate_tag_string(tag_tbl)
	--if tag_tbl is nil, returns an empty string
	if not tag_tbl then
		return ""
	end
	local tag_string = ""
	--for all entries of the table (not done with table.remove and table.concat, because it corrupts tag_tbl!!! :O )
	for i,v in ipairs(tag_tbl) do
		--if the tag does not start with the character "." (hidden tag), concatenates the tag
		if v:byte() ~= 46 then
			tag_string = tag_string.."["..v.."] "
		end
	end
	--returns table.concat of tag_tbl, enclosed by brackets
	return tag_string
end

--function apply_filter: checks all tags; if any tag matches with a rule, returns the corresponding action; if none matches, returns "deny" by default
local function apply_filter(tags, extra_tags)
	--initializes action and tag_match
	local action, tag_match
	--if logrules is nil, returns "deny"
	if not logrules then
		return "deny"
	end
	--for all rules
	for i,v in ipairs(logrules) do
		--extracts action and tag_match
		action, tag_match = v:match("([^ ]+) ([^ ]+)")
		--if tag_match is equal to "*" (wildcard that means "all")
		if tag_match == "*" then
			--returns the corresponding action
			return action
		end
		--if there is a global tags table
		if tags then
			--for each of the entries of the tags table
			for i,v in ipairs(tags) do
				--if TAG or .TAG matches the rule
				if v == tag_match or (v:byte() == 46 and v:sub(2) == tag_match) then
					--returns the corresponding action
					return action
				end
			end
		end
		--if there is a table of extra tags
		if extra_tags then
			--for each of the entries of the extra_tags table
			for i,v in ipairs(extra_tags) do
				--if TAG or .TAG matches the rule
				if v == tag_match or (v:byte() == 46 and v:sub(2) == tag_match) then
					--returns the corresponding action
					return action
				end
			end
		end
	end
	--if nothing matched, returns "deny"
	return "deny"
end

--function tbl2str: creates a printable string that shows the contents of a table
function tbl2str(name, order, in_data)
	--if in_data is a string, concatenates the value between quotes
	if type(in_data) == "string" then
		return name.."=\""..in_data.."\""
	--if it is a number, boolean or nil, concatenates the string version of it
	elseif type(in_data) == "number" or type(in_data) == "boolean" or type(in_data) == "nil" then
		return name.."="..tostring(in_data)
	end
	--if not, in_data is a table
	--creates a table to store all strings; more efficient to do a final table.concat than to concatenate all the way
	local out_tbl = {"table: "..name.."\n"}
	--indentation is a series of n x "\t" (tab characters), where n = order
	local indentation = string.rep("\t", order)
	--for all elements of the table
	for i,v in pairs(in_data) do
		--the start of the line is the indentation + table_indx
		table.insert(out_tbl, indentation..tbl2str(i, order+1, v).."\n")
	end
	--returns the concatenation of all lines
	return table.concat(out_tbl)
end

--function init_logger: initializes the logger
function init_logger(log_file, log_rules, log_batching, g_details, g_timestamp, g_elapsed)
	--global variables logfile, logrules and logbatching take values from the paremeters
	logfile = log_file
	logrules = log_rules
	logbatching = log_batching
	global_details = g_details
	global_timestamp = g_timestamp
	global_elapsed = g_elapsed
	--if log_file is "<print>" we are just printing in screen
	if log_file == "<print>" then
		--write_log is just equal to the io.write function
		write_log = io.write
	--if it is not the keyword "<print>" but it is still something
	elseif log_file then
		--write_log opens logfile, writes the line and closes it
		write_log = function(message)
			local logfile1 = io.open(logfile, "a")
			logfile1:write(message)
			logfile1:close()
		end
	end
end

--function new_logger: creates a logger object; tag_string is a string of tags separated by space; details, timestamp and elapsed are booleans
function new_logger(tag_string, details, timestamp, elapsed)
	--initializes the object logger
	local logger = {
		--generates a tag table and stores it in tags
		tags = string_deconcat(tag_string),
		details = global_details or details,
		timestamp = global_timestamp or timestamp,
		elapsed = global_elapsed or elapsed,
		log_tbl = {},
		--logflush writes the logs contained in self.log_tbl and then it cleans it
		logflush = function(self)
			if logbatching then
				write_log(table.concat(self.log_tbl))
				self.log_tbl = {}
			end
		end,
		--logprint is a function that contains the filtering and "decorative" tasks before printing the log line
		logprint = function(self, extra_tag_string, message, msg_details)
			--creates the extra_tags table from extra_tag_string
			local extra_tags = string_deconcat(extra_tag_string)
			--apply filters; if the result is "allow", prepares the log line
			if apply_filter(self.tags, extra_tags) == "allow" then
				--if the timestamp flag is set
				if self.timestamp then
					--inserts a timestamp at the start of the log line
					table.insert(self.log_tbl, string.format("%.6f: ", misc.time()))
				end
				--inserts the tags from the logger object
				table.insert(self.log_tbl, self.tag_string)
				--inserts the extra tags, inherent to the log line
				table.insert(self.log_tbl, generate_tag_string(extra_tags))
				--inserts the message
				table.insert(self.log_tbl, message)
				--if the details flag is set and msg_details is not nil
				if self.details and msg_details then
					--inserts the secondary message
					table.insert(self.log_tbl, "; "..msg_details)
				end
				--if the elapsed flag is set (to show elapsed time within a function)
				if self.elapsed then
					--inserts the elapsed time
					table.insert(self.log_tbl, string.format(". elapsed_time=%.6f", (misc.time()-self.start_time)))
				end
				table.insert(self.log_tbl, "\n")
				--if the flag logbatching is not set, flushes the logs automatically
				if not logbatching then
					write_log(table.concat(self.log_tbl))
					self.log_tbl = {}
				end
			end
		end,
		logprint_flush = function(self, extra_tag_string, message, msg_details)
			self:logprint(extra_tag_string, message, msg_details)
			self:logflush()
		end
	}
	--if the elapsed flag is set
	if logger.elapsed then
		--stores the start time for further calculations
		logger.start_time = misc.time()
	end
	--generates the tag string out of the tags table
	logger.tag_string = generate_tag_string(logger.tags)
	--returns the object
	return logger
end

function start_logger(tag_string, message, start_msg_details, details, timestamp, elapsed)
	local log1 = new_logger(tag_string, details, timestamp, elapsed)
	log1:logprint("START", start_message, start_msg_details)
	return log1
end

function start_end_logger(tag_string, message, msg_details, details, timestamp, elapsed)
	local log1 = new_logger(tag_string, details, timestamp, elapsed)
	log1:logprint_flush("START END", message, msg_details)
end