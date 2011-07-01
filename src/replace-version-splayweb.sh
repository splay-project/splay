#!/bin/bash

new_version=$1

find splayweb -name "*.rb" -exec ./change-header-splayweb.sh {} ${new_version} \;