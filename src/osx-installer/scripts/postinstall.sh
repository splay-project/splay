#!/bin/bash
#if 'SPLAY' is not already set in .bashrc..
if grep -q "SPLAY" $HOME/.bashrc ; then
	echo "nothing to do"
else
	cat >> $HOME/.bashrc << EOF
export PATH="/Applications/SPLAY/bin:$PATH"
LUA_PATH="/Applications/SPLAY/lualibs/?.lua;/opt/local/share/lua/5.1/?.lua"
LUA_CPATH="/Applications/SPLAY/clibs/?.so;/opt/local/lib/lua/5.1/?.so"
export LUA_PATH LUA_CPATH
EOF
source $HOME/.bashrc
fi

#set the custom folder
./seticon_ok -i splay.icns /Applications/SPLAY
#if the machine has the Developer Tools:

# according to http://daringfireball.net/2008/04/the_invisible_bit
# on HFS+ volumes it should be possible to set the invisibility bit of the custom icon
# with the following command:
chflags hidden /Applications/SPLAY/Icon$'\r'
# the script could be improved by  checking if SetFile is available. If so,
# it's  good idea to use it, as SetFile can enable the invisibility bit even
# on non HFS+  
#SetFile -a C /Applications/SPLAY/Icon$'\r'

#generate cert for splayd
cd /Applications/SPLAY/dist
cat >> gencerts.sh << EOF
#!/bin/bash
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
EOF
chmod a+x gencerts.sh
#./gencerts.sh

