#!/usr/bin/env python

import xmlrpclib
import sys
import urllib

if len(sys.argv) != 4:
	print "Usage: ./reset_slice.py pl_username pl_pwd pl_slice_name"
	sys.exit(2)

all_alive_nodes_query = "http://comon.cs.princeton.edu/status/tabulator.cgi?table=table_nodeviewshort&format=nameonly"
alive_nodes_query = "http://comon.cs.princeton.edu/status/tabulator.cgi?table=table_nodeviewshort&format=nameonly&persite=2&select='resptime>0"
alive_no_problems="http://comon.cs.princeton.edu/status/tabulator.cgi?format=nameonly&table=table_nodeviewshort&select='resptime%20%3E%200%20&&%20((drift%20%3E%201m%20||%20(dns1udp%20%3E%2080%20&&%20dns2udp%20%3E%2080)%20||%20gbfree%20%3C%205%20||%20sshstatus%20%3E%202h)%20==%200)'"
query=alive_no_problems
urllib.urlretrieve(query,"nodes.txt" )
api_server = xmlrpclib.ServerProxy('https://www.planet-lab.eu/PLCAPI/')
auth = {}
auth['Username'] = sys.argv[1] # <-- substitute your actual username here
auth['AuthString'] = sys.argv[2] # <-- substitute your actual password here
auth['AuthMethod'] = "password"


api_server = xmlrpclib.ServerProxy('https://www.planet-lab.eu/PLCAPI/')
auth = {}
auth['Username'] = sys.argv[1] # <-- substitute your actual username here
auth['AuthString'] = sys.argv[2] # <-- substitute your actual password here
auth['AuthMethod'] = "password"

slice_name=sys.argv[3]

# the slice's node ids
node_ids = api_server.GetSlices(auth,slice_name,['node_ids'])[0]['node_ids']
#for node in node_ids:
#    print node
api_server.DeleteSliceFromNodes(auth, sys.argv[3], node_ids)
