#The instructions to build the Packages.gz file are at:
# http://blog.petersen.vg/post/237815372/debfile
# From within the directory to use as deb repository, run:
# dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz

#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: makedeb_daemon.sh VER ARCH [i386,amd64]"
	exit
fi
ARCH=$2
if [[ $ARCH == "" ]]; then
	ARCH="i386"
fi

cp ../splayd_${VER}.tar.gz .
tar xzvf splayd_${VER}.tar.gz
cd splayd_${VER}
make splayd jobd splay_core.so misc_core.so data_bits_core.so luacrypto/crypto.so 
cd ..

PKG="liblua5.1-splayd_${ARCH}"
#remove old
rm ${PKG}.deb
#prepare the destination dir
rm -rf ${PKG}
mkdir -p ${PKG}/usr/share/lua/5.1/splay
mkdir -p ${PKG}/usr/lib/lua/5.1/splay
mkdir -p ${PKG}/usr/lib/splayd
#copy the files in appropriate locations
cp splayd_${VER}/splay_core.so ${PKG}/usr/lib/lua/5.1
cp splayd_${VER}/misc_core.so ${PKG}/usr/lib/lua/5.1/splay/
cp splayd_${VER}/data_bits_core.so ${PKG}/usr/lib/lua/5.1/splay/
cp splayd_${VER}/luacrypto/crypto.so ${PKG}/usr/lib/lua/5.1/
cp splayd_${VER}/modules/*lua ${PKG}/usr/share/lua/5.1
cp splayd_${VER}/modules/splay/*lua ${PKG}/usr/share/lua/5.1/splay/
cp splayd_${VER}/splayd ${PKG}/usr/lib/splayd/
cp splayd_${VER}/splayd.lua ${PKG}/usr/lib/splayd/
cp splayd_${VER}/settings.lua ${PKG}/usr/lib/splayd/
cp splayd_${VER}/jobd ${PKG}/usr/lib/splayd/
cp splayd_${VER}/jobd.lua ${PKG}/usr/lib/splayd/
cp splayd_${VER}/*cnf ${PKG}/usr/lib/splayd/

mkdir ${PKG}/DEBIAN
cat >> ${PKG}/DEBIAN/control << EOF
Package: splayd 
Version: ${VER}
Section: interpreters 
Priority: optional
Architecture: ${ARCH}
Essential: no
Depends: lua5.1, liblua5.1-0, liblua5.1-socket2, libssl0.9.8, liblua5.1-sec1 
Installed-Size: 1
Maintainer: Valerio Schiavoni [valerio dot schiavoni at gmail dot com]
Provides: package
Description:SPLAY Libs. 
  SPLAY simplifies the prototyping and development of large-scale distributed applications and 
  overlay networks. SPLAY covers the complete chain of distributed system design, development 
  and testing: from coding and local runs to controlled deployment, experiment control 
  and monitoring.
  SPLAY allows developers to specify their distributed applications in a concise way using a 
  specialized language based on Lua, a highly-efficient embeddable scripting language. 
  SPLAY applications execute in a safe environment with restricted access to local resources 
  (file system, network, memory) and can be instantiated on a large variety of testbeds composed 
  a large set of nodes with a single command.
  SPLAY is the outcome of research and development activities at the Computer Science Department 
  of the University of Neuchatel.
EOF

cat >> ${PKG}/DEBIAN/postinst << EOF
#!/bin/bash

touch /usr/lib/splayd/splayd.sh
echo -e '#!/bin/bash\ncd /usr/lib/splayd\n./splayd' > /usr/lib/splayd/splayd.sh
chmod 0775 /usr/lib/splayd/splayd.sh
cd /usr/bin
ln  ../lib/splayd/splayd.sh splayd

cd /usr/lib/splayd
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
echo "SPLAY Daemon and Libs installed."
echo "Edit /usr/lib/splayd/settings.lua with appropriate values, then execute 'splayd'"
EOF

chmod 0775 ${PKG}/DEBIAN/postinst


cat >> ${PKG}/DEBIAN/prerm << EOF
#!/bin/bash
rm /usr/bin/splayd
#rm /usr/bin/jobd
rm -rf /usr/lib/splayd/
EOF
chmod 0775 ${PKG}/DEBIAN/prerm

#make the deb
dpkg-deb --build ${PKG}

#clean the room
rm splayd_${VER}.tar.gz
rm -rf splayd_${VER}
rm -rf ${PKG}
mkdir -p ${VER}/${ARCH}
mv ${PKG}.deb ${VER}/${ARCH}/
dpkg-scanpackages ${VER}/${ARCH}/ /dev/null | gzip -9c > ${VER}/${ARCH}/Packages.gz

