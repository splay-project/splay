#!/bin/bash

new_version=$1

find controller -name "*.rb" -exec ./change-header-controller.sh {} ${new_version} \;