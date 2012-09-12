#!/bin/bash
kill -2 `ps aux | grep "ruby -rubygems controller" | grep -v "grep" | grep -v "bash" | sed s/'  *'/' '/g | cut -d' ' -f2`