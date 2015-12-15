Deploy and start using a fully-functional testbed with Docker Compose:

```bash
wget https://raw.githubusercontent.com/splay-project/splay/master/docker/docker-compose.yml 
docker-compose up -d
```
Done!

Now, you can log into the docker that runs the Splay Command-Line-Interface and start submitting Splay jobs:
```bash
docker exec -ti cli bash
cd /root/splay/src/rpc_client
./splay-start-session.lua
./splay-submit-job.lua -n 20 sample.lua
```

See a complete screencast:
[![asciicast](https://asciinema.org/a/31856.png)](https://asciinema.org/a/31856)
