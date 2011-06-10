-- Splay Distributed DB based on Dynamo architecture
-- Written by José Valerio
-- Neuchâtel 2011

-- REQUIRED LIBRARIES

-- base Splay lib
require"splay.base"
-- for operations with big headecimal strings
require"splay.bighex" --TODO see how to fit bighex library
-- support for Kyoto Cabinet DB
db	= require"splay.restricted_db"
-- for hashing
local crypto	= require"crypto"
-- for RPC calls
local rpc	= require"splay.rpc"
-- for the HTTP server
local net	= require"splay.net"
-- for enconding/decoding the bucket
local enc	= require"splay.benc"

-- LOCAL VARIABLES
local DEF_MAXKEYS = 1000

--INTERNAL FUNCTIONS

--function calculate_id: calculates the node ID from ID and port
function calculate_id(node)
	return crypto.evp.digest("sha1",node.ip..node.port)
end

--function get_closest_node_id: looks for the closest node to a given ID
function closest_node(id)
	local closest = neighborhood[1]
	--calculates the distance between the node and the ID
	local old_distance = bighex_circular_distance(id, closest.id)
	--for all other neighbors
	for i = 2, #neighborhood do
		--calculates the distance
		local distance = bighex_circular_distance(id, neighborhood[i].id)
		--compares both distances
		local compare = bighex_compare(old_distance, distance)
		--if distance is smaller or distance is equal and the id of the closest node is
		-- higher, replace closest with current neighbor
		if ((compare == 1) or ((compare == 0) and (bighex_compare(closest.id, neighborhood[i].id) == 1))) then
			closest = neighborhood[i]
			old_distance = distance
		end
	end
	--returns the closest node
	return closest
end

--function print_me: prints the IP address, port, and ID of the node
function print_me()
	log:print("ME",n.ip, n.port, n.id)
end

--function print_node: prints the IP address, port, and ID of a given node
function print_node(node)
	log:print(node.ip, node.port, node.id)
end

--APIs
--function join: adds the node to the dist-db network
function join()
	log:debug("I JOINED")
end

--function leave: removes the node from the dist-db network
function leave()
	log:debug("I LEFT")
end

--function parse_http_request: parses the payload of the HTTP request
function parse_http_request(socket)
	--print("\n\nHEADER\n\n")
	local first_line = socket:receive("*l")
	local first_line_analyzer = {}
	for piece in string.gmatch(first_line, "[^ ]+") do
		table.insert(first_line_analyzer, piece)
	end
	local method = first_line_analyzer[1]
	local resource = first_line_analyzer[2]
	local http_version = first_line_analyzer[3]
	local headers = {}
	while true do
		local data = socket:receive("*l")
		if ( #data < 1 ) then
			break
		end
		--print("data = "..data)
		local header_separator = string.find(data, ":")
		local header_k = string.sub(data, 1, header_separator-1)
		local header_v = string.sub(data, header_separator+2)
		--print(header_k, header_v)
		headers[header_k] = header_v
	end
	
	--local body = socket:receive(1) -- Receive 1 byte from the socket's buffer
	--print("\n\nBODY\n\n")
	-- initializes the request body read from client as empty string
	local bytes_left = tonumber(headers["content-length"] or headers["Content-Length"])
	local body = nil
	if bytes_left then
		--print("body length = "..bytes_left)
		body = socket:receive(bytes_left)
		--print("body = "..body)
	end
	
	return method, resource, http_version, headers, body
end

--REQUEST HANDLING FUNCTIONS

--function auth_auth: handles Authentication-Authorization as the Coordinator of the Access Key ID
function auth_auth(auth_info)
	log:debug(n.port.." handling a auth_auth request as Coordinator for access_key_id: "..auth_info.access_key_id)
	local service_value_encoded = db.get("db"..n.id, auth_info.access_key_id)
	if service_value_encoded then
		--TODO check signature with access_key_id, plaintext, signature
		local service_value = enc.decode(service_value_encoded)
		--returns both because some functions that call this function use the b-encoded
		-- version, and other use the table version
		return false, service_value_encoded, service_value
	end
	return "AccessDenied"
end

--function handle_register_service: handles a register request as the Coordinator of the Access Key ID
-- used only to complement functionality, but it's not on the S3 APIs
function handle_register_service(auth_info)
	log:debug(n.port.." handling a register request as Coordinator for access_key_id: "..auth_info.access_key_id.."; display_name: "..auth_info.display_name)
	if not db.get("db"..n.id, auth_info.access_key_id) then
		local service_value = {
			access_key_id = auth_info.access_key_id,
			display_name = auth_info.display_name,
			secret_key = auth_info.secret_key,
			buckets = {}
			}
		local service_value_encoded = enc.encode(service_value)
		log:debug(n.port..": service value is:", service_value_encoded)
		db.set("db"..n.id, auth_info.access_key_id, service_value_encoded)
		return false
	end
	return "ServiceAlreadyExists"
	
end

--function handle_get_service: handles a GET SERVICE request as the Coordinator of the Access Key ID
function handle_get_service(auth_info)
	log:debug(n.port..": handling a GET SERVICE as Coordinator for access_key_id: "..auth_info.access_key_id)
	local err, service_value_encoded, service_value = auth_auth(auth_info)
	log:debug(n.port..": service value is:", service_value_encoded)
	--TODO process value
	local service_value = service_value_encoded
	return err, service_value
end

--function handle_get_bucket: handles a GET BUCKET request as the Coordinator of the Access Key ID
function handle_get_bucket(auth_info, bucket)
	log:debug(n.port.." handling a GET BUCKET as Coordinator for access_key_id: "..auth_info.access_key_id.."; bucket: "..bucket)
	local err, service_value_encoded, service_value = auth_auth(auth_info)
	if not err then
		local bucket_value = service_value.buckets[bucket]
		if bucket_value then
			log:debug(n.port..": bucket value is:", bucket_value)
			--TODO cover search keywords
			local bucket_value_encoded = enc.encode(bucket_value)
			return false, bucket_value_encoded
		end
		return "NoSuchBucket"
	end
	return err
end

--function handle_put_bucket: handles a PUT BUCKET request as the Coordinator of the Access Key ID
function handle_put_bucket(auth_info, bucket)
	log:debug(n.port.." handling a PUT BUCKET as Coordinator for access_key_id: "..auth_info.access_key_id.."; bucket: "..bucket)
	local err, service_value_encoded, service_value = auth_auth(auth_info)
	if not err then
		if not service_value.buckets[bucket] then
			log:debug(n.port..": old service value is:", service_value_encoded)
			service_value.buckets[bucket] = {name="bucket", objects={}}
			service_value_encoded = enc.encode(service_value)
			log:debug(n.port..": new service value is:", service_value_encoded)
			db.set("db"..n.id, auth_info.access_key_id, service_value_encoded)
			return false
		end
		return "BucketAlreadyExists"
	end
	return err
end

--function handle_delete_bucket: handles a DELETE BUCKET request as the Coordinator of the Access Key ID
function handle_delete_bucket(auth_info, bucket)
	log:debug(n.port..": handling a DELETE BUCKET as Coordinator for access_key_id: "..auth_info.access_key_id.."; bucket: "..bucket)
	local err, service_value_encoded, service_value = auth_auth(auth_info)
	if not err then
		if service_value.buckets[bucket] then
			local bucket_not_empty = false
			for i,v in pairs(service_value.buckets[bucket].objects) do
				bucket_not_empty = true
				break
			end
			--TODO check if there is a better way to see if table is empty
			if bucket_not_empty then
				return "BucketNotEmpty"
			end
			service_value.buckets[bucket] = nil
			log:debug(n.port..": old service value is:", service_value_encoded)
			service_value_encoded = enc.encode(service_value)
			log:debug(n.port..": new service value is:", service_value_encoded)
			db.set("db"..n.id, auth_info.access_key_id, service_value_encoded)
			return false
		end
		return "NoSuchBucket"
	end
	return err
end

--function handle_new_object_in_bucket: inserts an Object into the Bucket as the Coordinator of the Access Key ID, if
-- the Object is not there; if it is there, it updates its details
function handle_new_object_in_bucket(auth_info, bucket, object, size)
	log:debug(n.port..": handling a new object in bucket as Coordinator for access_key_id: "..auth_info.access_key_id.."; bucket: "..bucket.."; object: "..object.." and size: "..size)
	local err, service_value_encoded, service_value = auth_auth(auth_info)
	if not err then
		local bucket_value = service_value.buckets[bucket]
		if bucket_value then
			log:debug(n.port..": old service value is:", service_value_encoded)
			--all this "ifs" below could be avoided if one doesn't care about DB writes,
			-- but like this one, can avoid writing unnecessarily on the DB
			if bucket_value.objects[object] then
				if bucket_value.objects[object].size ~= size then
					service_value.buckets[bucket].objects[object].size = size
					service_value_encoded = enc.encode(service_value)
					log:debug(n.port..": new service value is:", service_value_encoded)
					db.set("db"..n.id, auth_info.access_key_id, service_value_encoded)
				else
					log:debug(n.port..": service value didn't change")
				end
			else
				service_value.buckets[bucket].objects[object] = {size = size}
				service_value_encoded = enc.encode(service_value)
				log:debug(n.port..": new service value is:", service_value_encoded)
				db.set("db"..n.id, auth_info.access_key_id, service_value_encoded)
			end
			return false
		end
		return "NoSuchBucket"
	end
	return err
end

--function handle_remove_object_from_bucket: removes an Object from the Bucket as the Coordinator of the Access Key ID and
-- if there is an error, returns a string describing it; if not, returns false
function handle_remove_object_from_bucket(auth_info, bucket, object)
	log:debug(n.port..": handling a remove object from bucket as Coordinator for access_key_id: "..auth_info.access_key_id.."; bucket: "..bucket.."; object: "..object)
	local err, service_value_encoded, service_value = auth_auth(auth_info)
	if not err then
		local bucket_value = service_value.buckets[bucket]
		if bucket_value then
			log:debug(n.port..": old service value is:", service_value_encoded)
			if bucket_value.objects[object] then
				service_value.buckets[bucket].objects[object] = nil
				service_value_encoded = enc.encode(service_value)
				log:debug(n.port..": new service value is:", service_value_encoded)
				db.set("db"..n.id, auth_info.access_key_id, service_value_encoded)
				return false
			end
			return "NoSuchKey"
		end
		return "NoSuchBucket"
	end
	return err
end

--function handle_get_object: handles a GET OBJECT request as the Bucket/Object coordinator and returns the value of the object
function handle_get_object(bucket, object)
	log:debug(n.port..": handling a GET OBJECT as Coordinator for bucket: "..bucket..", object: "..object)
	local value = db.get("db"..n.id, bucket.."/"..object)
	log:debug(n.port..": object value is:", value)
	return value
end

--function handle_put_object: handles a PUT OBJECT request as the Bucket/Object coordinator
function handle_put_object(bucket, object, value)
	log:debug(n.port..": handling a PUT OBJECT as Coordinator for bucket: "..bucket..", object: "..object.."; value: "..value)
	db.set("db"..n.id, bucket.."/"..object, value)
end

--function handle_delete_object: handles a DELETE OBJECT request as the Bucket/Object coordinator
function handle_delete_object(bucket, object)
	log:debug(n.port..": handling a DELETE OBJECT as Coordinator for bucket: "..bucket..", object: "..object)
	db.remove("db"..n.id, bucket.."/"..object)
end


--FORWARDING FUNCTIONS

--function forward_register_service: forwards a register request to the coordinator of the given Access Key ID
function forward_register_service(auth_info)
	log:debug(n.port..": received a register request for access_key_id: "..auth_info.access_key_id)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err = rpc.call(closest_to_service_key, {'handle_register_service', auth_info})
	return err
end

--function forward_get_service: forwards a GET SERVICE request to the coordinator of the given Access Key ID
function forward_get_service(auth_info)
	log:debug(n.port..": received a GET SERVICE for access_key_id: "..auth_info.access_key_id)
	--TODO access_key_id is just a username, no AA
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err, service_value_encoded = rpc.call(closest_to_service_key, {'handle_get_service', auth_info})
	if err then
		return err
	end
	local service_value = enc.decode(service_value_encoded)
	--TODO modify this answer to service
	local answer = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"..
			"<ListAllMyBucketsResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01\">\n"..
			"   <Owner>\n"..
			"      <ID>"..service_value.access_key_id.."</ID>\n"..
			"      <DisplayName>"..service_value.display_name.."</DisplayName>\n"..
			"   </Owner>\n"..
			"   <Buckets>\n"
	for i,v in pairs(service_value.buckets) do
		answer = answer..
			"      <Bucket>\n"..
			"         <Name>"..i.."</Name>\n"..
			--"         <CreationDate>"..v.created_at.."</CreationDate>\n"..
			"      </Bucket>\n"
	end
	answer = answer.."   </Buckets>\n</ListAllMyBucketsResult>"
	log:debug(n.port..": service value is:\n"..answer)
	return false, answer
end

--function forward_get_bucket: forwards a GET BUCKET request to the coordinator of the Access Key ID
function forward_get_bucket(auth_info, bucket)
	log:debug(n.port..": received a GET BUCKET for access_key_id: "..auth_info.access_key_id..", bucket: "..bucket)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err, bucket_value_encoded = rpc.call(closest_to_service_key, {'handle_get_bucket', auth_info, bucket})
	if err then
		return err
	end
	local bucket_value = enc.decode(bucket_value_encoded)
	local answer = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"..
			"<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01\">\n"..
			"   <Name>"..bucket_value.name.."</Name>\n"
	if not bucket_value.prefix then
		answer = answer.."   <Prefix/>\n"
	else
		answer = answer.."   <Prefix>"..prefix.."<Prefix/>\n"
	end
	if not bucket_value.marker then
		answer = answer.."   <Marker/>\n"
	else
		answer = answer.."   <Marker>"..bucket_value.marker.."<Marker/>\n"
	end
	answer = answer.."   <MaxKeys>"..(bucket_value.maxkeys or DEF_MAXKEYS).."</MaxKeys>\n"
	if bucket_value.truncated then
		answer = answer.."   <IsTruncated>true</IsTruncated>\n"
	else
		answer = answer.."   <IsTruncated>false</IsTruncated>\n"
	end
	for i,v in pairs(bucket_value.objects) do
		answer = answer..
			"   <Contents>\n"..
			"      <Key>"..i.."</Key>\n"..
			--"      <LastModified>2009-10-12T17:50:30.000Z</LastModified>\n"..
			--"      <ETag>&quot;fba9dede5f27731c9771645a39863328&quot;</ETag>\n"..
			"      <Size>"..v.size.."</Size>\n"..
			"      <StorageClass>STANDARD</StorageClass>\n"..
			"      <Owner>\n"..
			"         <ID>"..auth_info.access_key_id.."</ID>\n".. --TODO is this the Access_Key_ID? looks redundant
			--"         <DisplayName>mtd@amazon.com</DisplayName>\n".. --TODO look how to piggyback DisplayName
			"      </Owner>\n"..
			"   </Contents>\n"
	end
	answer = answer.."</ListBucketResult>"
	log:debug("value for bucket: "..bucket.." is:", answer)
	return false, answer
end

--function forward_put_bucket: forwards a PUT BUCKET request to the Bucket/Object coordinator
function forward_put_bucket(auth_info, bucket)
	log:debug(n.port..": received a PUT BUCKET for access_key_id: "..auth_info.access_key_id..", bucket: "..bucket)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err = rpc.call(closest_to_service_key, {'handle_put_bucket', auth_info, bucket})
	return err
end

--function forward_delete_bucket: forwards a DELETE BUCKET request to the Bucket/Object coordinator
function forward_delete_bucket(auth_info, bucket)
	log:debug(n.port..": received a DELETE BUCKET for access_key_id: "..auth_info.access_key_id..", bucket: "..bucket)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err = rpc.call(closest_to_service_key, {'handle_delete_bucket', auth_info, bucket})
	return err
end

--function forward_get_object: forwards a GET OBJECT request to the Bucket/Object coordinator
function forward_get_object(auth_info, bucket, object)
	log:debug(n.port..": received a GET OBJECT for access_key_id: "..auth_info.access_key_id..", bucket: "..bucket..", object: "..object)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err, service_value_encoded, service_value  = rpc.call(closest_to_service_key, {'auth_auth', auth_info})
	if err then
		return err
	end
	if service_value.buckets[bucket] then
		if service_value.buckets[bucket].objects[object] then
			local object_key = crypto.evp.digest("sha1", bucket.."/"..object)
			log:debug(n.port..": object key is "..object_key)
			log:debug(n.port..": closest node is")
			local closest_to_object_key = closest_node(object_key)
			print_node(closest_to_object_key)
			local object_value = rpc.call(closest_to_object_key, {'handle_get_object', bucket, object})
			log:debug(n.port..": value for bucket: "..bucket..", object: "..object.." is: ", object_value)
			return false, object_value
		end
		return "NoSuchKey"
	end
	return "NoSuchBucket"
	
end

--function forward_put_object: forwards a PUT OBJECT request to the Bucket/Object coordinator and requests the
-- coordinator of the Access Key ID to update the list of Objects in the Bucket
function forward_put_object(auth_info, bucket, object, value)
	log:debug(n.port..": received a PUT OBJECT for access_key_id: "..auth_info.access_key_id..", bucket: "..bucket..", object: "..object)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	local object_size = #value
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err = rpc.call(closest_to_service_key, {'handle_new_object_in_bucket', auth_info, bucket, object, object_size})
	if err then
		return err
	end
	local object_key = crypto.evp.digest("sha1", bucket.."/"..object)
	log:debug("object key is "..object_key)
	log:debug("closest node to object key is")
	local closest_to_object_key = closest_node(object_key)
	print_node(closest_to_object_key)
	events.thread(function()
		rpc.call(closest_to_object_key, {'handle_put_object', bucket, object, value})
	end)
	return false
end

--function forward_delete_object: forwards a DELETE OBJECT request to the Bucket/Object coordinator and requests the
-- coordinator of the Access Key ID to update the list of Objects in the Bucket
function forward_delete_object(auth_info, bucket, object)
	log:debug(n.port..": received a DELETE OBJECT for access_key_id: "..auth_info.access_key_id..", bucket: "..bucket..", object: "..object)
	local service_key = crypto.evp.digest("sha1", auth_info.access_key_id)
	log:debug(n.port..": service key is "..service_key)
	log:debug(n.port..": closest node is")
	local closest_to_service_key = closest_node(service_key)
	print_node(closest_to_service_key)
	local err = rpc.call(closest_to_service_key, {'handle_remove_object_from_bucket', auth_info, bucket, object})
	if err then
		return err
	end
	local object_key = crypto.evp.digest("sha1", bucket.."/"..object)
	log:debug("object key is "..object_key)
	log:debug("closest node to object key is")
	local closest_to_object_key = closest_node(object_key)
	print_node(closest_to_object_key)
	events.thread(function()
		rpc.call(closest_to_object_key, {'handle_delete_object', bucket, object})
	end)
	return false
end


--TABLE OF FORWARDING FUNCTIONS

local forward_request = {
	["REGISTER_service"] = forward_register_service,
	["GET_service"] = forward_get_service,
	["GET_bucket"] = forward_get_bucket,
	["GET_object"] = forward_get_object,
	["PUT_bucket"] = forward_put_bucket,
	["PUT_object"] = forward_put_object,
	["DELETE_bucket"] = forward_delete_bucket,
	["DELETE_object"] = forward_delete_object
	}


--FRONT-END FUNCTIONS

--function handle_http_message: handles the incoming messages (HTTP requests)
function handle_http_message(socket)
	local client_ip, client_port = socket:getpeername()
	local method, resource, http_version, headers, body = parse_http_request(socket)
	local key = string.sub(resource, 2)
	log:debug(n.port..": resource is "..resource)
	log:debug(n.port..": requesting for "..key)
	local bucket_object_separator = string.find(key, "/")
	local host = headers["Host"] or headers["host"]
	local bucket = nil
	local object = nil
	if bucket_object_separator then
		bucket = string.sub(key, 1, bucket_object_separator-1)
		object = string.sub(key, bucket_object_separator+1)
	elseif host ~= "splay-project.org" then
		bucket = string.sub(host, 1, -19)
		if #key ~= 0 then
			object = key
		end
	elseif key ~= "" then
		bucket = key
	end
	
	local auth_info_string = headers["Authorization"] or headers["authorization"]
	local auth_info_separator = string.find(auth_info_string, "/")
	local auth_info = {}
	if auth_info_separator then
		auth_info.access_key_id = string.sub(auth_info_string, 1, auth_info_separator-1)
		auth_info_string = string.sub(auth_info_string, auth_info_separator+1)
		auth_info_separator = string.find(auth_info_string, "/")
		auth_info.display_name = string.sub(auth_info_string, 1, auth_info_separator-1)
		auth_info.secret_key = string.sub(auth_info_string, auth_info_separator+1)
		log:debug(n.port..": auth_info: access_key_id: "..auth_info.access_key_id..", display_name: "..auth_info.display_name..", secret_key: "..auth_info.secret_key)
	else
		auth_info.access_key_id = auth_info_string
		log:debug(n.port..": auth_info: access_key_id: "..auth_info.access_key_id)
	end
	--TODO check if the field Authorization exists
	--TODO refine this stuff
	
	if bucket then
		if object then
			requested_element = "_object"
		else
			requested_element = "_bucket"
		end
	else
		requested_element = "_service"
	end
	
	local value = body
	log:debug(n.port..": http request parsed, a "..method..requested_element.." request will be forwarded")
	log:debug(n.port..": args: bucket:", bucket, "object:", object, "value:", value)
	local err, answer = forward_request[method..requested_element](auth_info, bucket, object, value)
	
	local http_response_body = nil
	local http_response_code = nil
	local http_response_content_type = nil
	if err then
		if err == "NoSuchBucket" or err == "NoSuchKey" then
			http_response_code = "404 Not Found"
		elseif err == "AccessDenied" then
			http_response_code = "403 Forbidden"
		elseif err == "ServiceAlreadyExists" or err == "BucketNotEmpty" or err == "BucketAlreadyExists" then
			http_response_code = "409 Conflict"
		end
		
		http_response_body =
			"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n"..
			"<Error>\r\n"..
			"  <Code>"..err.."</Code>\r\n"
			--"  <Message>The resource you requested does not exist</Message>\r\n" --TODO message can change
		if object then
			http_response_body = http_response_body.."  <Resource>/"..bucket.."/"..object.."</Resource>\r\n".. 
			--  <RequestId>4442587FB7D0A2F9</RequestId>
			"</Error>"
		elseif bucket then
			http_response_body = http_response_body.."  <Resource>/"..bucket.."</Resource>\r\n".. 
			--  <RequestId>4442587FB7D0A2F9</RequestId>
			"</Error>"
		else
			http_response_body = http_response_body.."  <Resource>/</Resource>\r\n".. 
			--  <RequestId>4442587FB7D0A2F9</RequestId>
			"</Error>"
		end
		
		http_response_content_type = "application/xml"
	else
		http_response_code = "200 OK"
		http_response_content_type = "text/plain"
		http_response_body = answer
	end
	
	local http_response = "HTTP/1.1 "..http_response_code.."\r\n"
	if http_response_body then
		http_response = http_response..
			"Content-Length: "..#http_response_body.."\r\n"..
			"Content-Type: "..http_response_content_type.."\r\n\r\n"..http_response_body
	else
		http_response = http_response.."\r\n"
	end
	
	socket:send(http_response)
-- 	if string.sub(header,1,8) == "OPTIONS" then
-- 		return handle_options_method(socket) 
-- 	else
-- 		handle_post_method(socket,jsonmsg)
-- 	end
end





--GOSSIP-BASED PROTOCOL TO INFORM ABOUT JOINS AND LEAVES
--COMING SOON...


--function init_node: initializes the node
function init_node()
	--takes IP address and port from job.me
	n = {ip=job.me.ip, port=job.me.port}
	--initializes the randomseed with the port
	math.randomseed(n.port)
	--calculates the ID by hashing the IP address and port
	n.id = calculate_id(job.me)
	--initializes the neighborhood as an empty table
	neighborhood = {}
	--for all nodes on job.nodes
	for _,v in ipairs(job.nodes) do
		--copies IP address, port and calculates the ID from them
		table.insert(neighborhood, {
			ip = v.ip,
			port = v.port,
			id = calculate_id(v)
		})
	end
	
	--server listens through the rpc port + 1
	local http_server_port = n.port+1
	--puts the server on listen
	net.server(http_server_port, handle_http_message)

-- 	print("PRINTING IO")
-- 	for i,v in pairs(io) do
-- 		print(i, type(v))
-- 	end
-- 	print("PRINTING DB")
-- 	for i,v in pairs(db) do
-- 		print(i, type(v))
-- 	end
	--splaydb.open("dist-db","hash", db.OWRITER + db.OCREATE) VERSION WITH FLAGS
	db.open("db"..n.id,"hash")
	
	--starts the RPC server for internal communication
	rpc.server(n.port)
	
	--PRINTING STUFF
	--prints a initialization message
	print("HTTP server - Started on port "..http_server_port)
	print_me()
	for _,v in ipairs(neighborhood) do
                print_node(v)
        end
	for _,v in ipairs(neighborhood) do
                log:print("\t"..(tonumber(v.port)+1)..",")
        end
end


--MAIN FUNCTION
events.run(function()
	log.global_level = 1
	init_node()
-- 	events.sleep(10)
-- 	random_indx = math.random(#job.nodes)
-- 	random_key = crypto.evp.digest("sha1",math.random(1000000))
-- 	rpc.call(job.nodes[random_indx], {'forward_put', random_key, n.port})
-- 	random_indx = math.random(#job.nodes)
-- 	answer = rpc.call(job.nodes[random_indx], {'forward_get', random_key})
-- 	print("answer is: "..answer)
end)