#Splay TestBed Cluster Management Scripts
Author: valerio.schiavoni@gmail.com

This is a set of scripts to easily manage a splay testbed deployed on a cluster.

###Assumptions
The scripts assume that:
- All the machines of the Splay cluster are configured with the same OS  
- The same username/password for the same user exists across the machines
- The scripts are operated from the Splay controller's machine
- The controller is running
- The Splay libraries and binaries are installed in the default location used by the .deb package: if not, adjust the variable SPLAY\_INSTALL\_DIR in install\_splay\_nodes.sh script; 

###How to use
- Edit cluster_hosts.txt: one IP per line, with the IPs of the machines that will run the splay deamons
- Generate a new keypair for this Splay cluster: $ssh-keygen. By default it will create a new public key in ~/.ssh/id_rsa.pub;
- Edit copy-id.sh and adjust: the variables USERNAME/PASSWORD, and the path to the public key generated in 2);
- Execute: ./copy-id.sh;
- Execute: ./copy-on-cluster.sh install_splay_nodes.sh;
- Finally, to launch 10 splayds on each machine: ./remote_pilot.sh "./install_splay_nodes.sh 10 IP_SPLAY_CONTROLLER"; 

###Misc
The script remote_pilot.sh can execute any command on all the machines of the cluster, including 'rm -rf': *be careful*.
 
