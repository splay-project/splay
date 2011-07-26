#!/bin/bash
grep "Offending key" logs/*  | cut -d ":" -f 3 | sort -n -r | tr '\r' '\n' |xargs -I{} sed -ie {}d ~/.ssh/known_hosts
