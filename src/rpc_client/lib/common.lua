--function load_config: loads the config file
function load_config()
	local config_file = loadfile("splay_cli_config.lua")
	if pcall(config_file) then
		cli_server_url_from_conf_file = config.cli_server_url
		username_from_conf_file = config.username
		password_from_conf_file = config.password
	end
end

--function print_usage: shows the usage and exits
function print_usage()
	print("Usage: lua "..command_name..".lua [OPTION] "..other_mandatory_args.."CLI_SERVER_URL\n")
	print("Mandatory arguments to long options are mandatory for short options too.")
	for i,v in ipairs(usage_options) do
		print(v)
	end
	print("-i, --cli_server_as_ip_addr\tthe URL of the CLI server is entered as an IP address and it")
	print("\t\t\t\tis automatically completed as http://A.B.C.D:2222/json-rpc (default config for rpc_server)")
	print("-h, --help\t\t\tdisplays this help and exit\n")
	os.exit()
end

function check_min_arg()
	--if min_arg_ok is false (the required arguments were not filled)
	if not min_arg_ok then
		--prints an error message
		print("missing arguments\n")
		--prints the usage
		print_usage()
	end
end

function check_cli_server()
	--if a SPLAY CLI server was already passed as argument of the command
	if cli_server_url then
		--if cli_server_as_ip_addr is true
		if cli_server_as_ip_addr then
			--the URL is completed with the default port and page
			cli_server_url = "http://"..cli_server_url..":2222/json-rpc"
		end
	--if no SPLAY CLI was passed as argument
	else
		--prints a message
		print("No SPLAY CLI server URL specified. Using SPLAY CLI server URL from the configuration file...\n")
		--takes the CLI server from the config file
		cli_server_url = cli_server_url_from_conf_file
	end

	--if the URL does not start with the string "http://"
	if not string.match(cli_server_url,"^http://") then
		--prints an error message
		print("Invalid URL:"..cli_server_url.."\nA valid URL must have the following syntax: \"http://webserver[:port][/page]\"\nExamples of valid URLs:\n\thttp://127.0.0.1/\n\thttp://some.website.com/json-rpc\n\thttp://10.0.0.1:2222/\n")
		--exits
		os.exit()
	end
end

function check_username(checked_username, username_type)
	--if username was not provided on the command
	if not checked_username then
		--if a username was specified on the configuration file
		if (username_type == "Username" or username_type == "Administrator's username") and username_from_conf_file then
			--prints a message
			print(username_type.." taken from the configuration file...\n")
			checked_username = username_from_conf_file
		--if not
		else
			--asks for the username
			print(username_type..":")
			checked_username = io.read()
		end
	end
	return(checked_username)
end

function check_password(checked_password, password_type)
	--if password was not provided on the command
	if not checked_password then
		--if a password was specified on the configuration file
		if (password_type == "Password" or password_type == "Current password" or password_type == "Administrator's password") and password_from_conf_file then
			--prints a message
			print(password_type.." taken from the configuration file...\n")
			checked_password = password_from_conf_file
		--if not
		else
			checked_password = ""
			--asks for the password
			print(password_type..":")
			os.execute("stty raw -echo")
			--reads keystroke by keystroke until ENTER is pressed, in a silent way (is not displayed on screen)
			while true do
				local one_keystroke = io.read(1)
				if one_keystroke == string.char(13) then break end
				checked_password = checked_password..one_keystroke
			end
			os.execute("stty sane")
			print()
		end
	end
	return(checked_password)
end

function check_session_id()
	--opens the session_id file
	local hashed_cli_server_url = sha1(cli_server_url)
	local session_id_file = io.open("."..hashed_cli_server_url..".session_id","r")
	--if the file exists
	if session_id_file then
		--reads the session_id from the file
		session_id = session_id_file:read("*a")
		--closes the file
		session_id_file:close()
	else
		--prints an error message
		print("At the moment, there is no active session for SPLAY CLI server: "..cli_server_url.."\n\nPlease start a session with splay-start-session before attempting a command.\n")
		--exits
		os.exit()
	end
end

function check_response(response)
	if response then
		local json_response = json.decode(response)
		if json_response.result then
			if json_response.result.ok == true then
				--prints the result
				print("Response from "..cli_server_url..":")
				return true
			else
				print("Response from "..cli_server_url..":")
				if json_response.result.error then
					print("Error: "..json_response.result.error.."\n")
				else
					print("Error\n")
				end
			end
		else
			print("Result not OK in response from "..cli_server_url)
			print("Error: "..json_response.error)
			print("Please report this error to the SPLAY CLI server administrator\n")
		end
	--if not
	else
		--prints that there was no response
		print("No response from server "..cli_server_url)
		print("Please check the SPLAY CLI server URL and if the server is running\n")
	end
	return false
end
