dist_data_DATA=client.cnf root.cnf
all: cert
cert:
	openssl req -newkey rsa:1024 -sha1 -keyout rootkey.pem -out rootreq.pem \
		-nodes -config ./root.cnf -days 365 -batch
	openssl x509 -req -in rootreq.pem -sha1 -extfile ./root.cnf \
  		-extensions v3_ca -signkey rootkey.pem -out root.pem -days 365
	openssl x509 -subject -issuer -noout -in root.pem
	openssl req -newkey rsa:1024 -sha1 -keyout key.pem -out req.pem \
  		-nodes -config ./client.cnf -days 365 -batch
	openssl x509 -req -in req.pem -sha1 -extfile ./client.cnf \
  		-extensions usr_cert -CA root.pem -CAkey rootkey.pem -CAcreateserial \
		-out cert.pem -days 365
	cat cert.pem root.pem > client.pem
	openssl x509 -subject -issuer -noout -in client.pem
