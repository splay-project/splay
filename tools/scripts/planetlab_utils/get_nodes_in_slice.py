#!/usr/bin/env python

import xmlrpclib
import sys
import urllib

if len(sys.argv) != 4:
	print "Usage: ./get_nodes_in_slice.py pl_username pl_pwd pl_slice_name"
	sys.exit(2)

api_server = xmlrpclib.ServerProxy('https://www.planet-lab.eu/PLCAPI/')
auth = {}
auth['Username'] = sys.argv[1] # <-- substitute your actual username here
auth['AuthString'] = sys.argv[2] # <-- substitute your actual password here
auth['AuthMethod'] = "password"

slice_name=sys.argv[3]

# the slice's node ids
node_ids = api_server.GetSlices(auth,slice_name,['node_ids'])[0]['node_ids']

# get hostname for these nodes
slice_nodes = api_server.GetNodes(auth,node_ids,['hostname'])

# store in a file
f=open(slice_name+'_nodes.txt','w')
for node in slice_nodes:
    print >>f,node['hostname']
f.close()
print "Nodes list written in file: "+slice_name+'_nodes.txt'
