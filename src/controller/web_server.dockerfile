from ubuntu:12.04
label Description="TBD"

run mkdir -p /usr/splay

workdir /usr/splay

run apt-get update && apt-get -y --no-install-recommends install \
  build-essential ruby1.8-full rubygems1.8 less libmysqlclient-dev libssl-dev

run gem install json -v 1.8.6 && gem install openssl-nonblock dbi dbd-mysql mysql Orbjson

add cli-server ./cli-server
add lib ./lib
add deploy_web_server.sh .
