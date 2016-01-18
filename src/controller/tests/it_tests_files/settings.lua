splayd.settings.key = "host_1_1" -- received at the registration

splayd.settings.name = "host_1_1"

splayd.settings.controller.ip = "127.0.0.1"
splayd.settings.controller.port = 11000

-- Set to "grid" to support native libs
splayd.settings.protocol = "standard"

-- all sizes are in bytes
splayd.settings.job.max_number = 4
splayd.settings.job.max_mem = 1368709120 
splayd.settings.job.max_size = 4 * 1024 * 1024 * 1024 
splayd.settings.job.disk.max_files = 1024
splayd.settings.job.disk.max_file_descriptors = 1024
splayd.settings.job.network.max_send = 1024 * 1024 * 1024 * 1024 
splayd.settings.job.network.max_receive = 1024 * 1024 * 1024 * 1024 
splayd.settings.job.network.max_sockets = 1024
splayd.settings.job.network.max_ports = 64
splayd.settings.job.network.start_port = 22000
splayd.settings.job.network.end_port = 32000

-- Information about your connection (or your limitations)
-- Enforce them with trickle or other tools
splayd.settings.network.send_speed = 1024 * 1024
splayd.settings.network.receive_speed = 1024 * 1024
