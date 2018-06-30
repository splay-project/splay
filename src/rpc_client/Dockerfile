from ubuntu:12.04
label Description="TBD"

run mkdir /usr/splay
workdir /usr/splay

run apt-get update && \
  apt-get -y --no-install-recommends install \
  lua5.1 liblua5.1-socket2 liblua5.1-json

add *.* ./
add lib ./lib
