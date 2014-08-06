#!/usr/bin/env python

import xmlrpclib
import sys
import urllib

if len(sys.argv) != 5:
	print "Usage: ./add_nodes_to_slice.py pl_username pl_pwd pl_slice_name list_of_nodes.txt"
	sys.exit(2)

input_file=sys.argv[4]
api_server = xmlrpclib.ServerProxy('https://www.planet-lab.eu/PLCAPI/')
auth = {}
auth['Username'] = sys.argv[1] # <-- substitute your actual username here
auth['AuthString'] = sys.argv[2] # <-- substitute your actual password here
auth['AuthMethod'] = "password"

node_list = [line.strip() for line in open(input_file)]
api_server.AddSliceToNodes(auth, sys.argv[3], node_list)
