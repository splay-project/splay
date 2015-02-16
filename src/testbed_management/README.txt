---Splay TestBed Cluster Management Scripts---
Author: valerio.schiavoni@gmail.com

- Assumptions
The scripts assume that all the machines of the Splay cluster are configured with the same OS and 
the same username/password for the same user.
The scripts are operated from the Splay controller's machine.

- How to use
1) Edit cluster_hosts.txt: one IP per line, with the IPs of the machines that will run the splay deamons;
2) Generate a new keypair for this Splay cluster: $ssh-keygen. By default it will create a new public key in ~/.ssh/id_rsa.pub;
3) Edit copy-id.sh and adjust: the variables USERNAME/PASSWORD, and the path to the public key generated in 2);
4) Execute: ./copy-id.sh;
5) Execute: ./copy-on-cluster.sh install_splay_nodes.sh;
6) Finally, to launch 10 splayds on each machine: ./remote_pilote.sh "./install_splay_nodes.sh 10 IP_SPLAY_CONTROLLER"; 

- Misc
The script remote_pilote.sh can execute any command on all the machines of the cluster, including 'rm -rf'. 
 
