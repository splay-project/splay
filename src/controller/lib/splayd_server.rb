require File.expand_path(File.join(File.dirname(__FILE__), 'splayd_protocol'))
require File.expand_path(File.join(File.dirname(__FILE__), 'splayd_grid_protocol'))

class SplaydServer

	@@ssl = SplayControllerConfig::SSL
	@@splayd_threads = {}
	def self.threads() return @@splayd_threads end
	def self.threads=(threads) @@splayd_threads = threads end

	def initialize(port = nil)
		@port = port || SplayControllerConfig::SplaydPort
	end

	def run
		return Thread.new() do
			main
		end
	end

	def main
		begin
			server = TCPServer.new(@port)
			server.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)

			if @@ssl
				# SSL key and cert
				key = OpenSSL::PKey::RSA.new 512
				cert = OpenSSL::X509::Certificate.new
				cert.not_before = Time.now
				cert.not_after = Time.now + 3600
				cert.public_key = key.public_key
				cert.sign(key, OpenSSL::Digest::SHA1.new)

				# SSL context
				ctx = OpenSSL::SSL::SSLContext.new
				ctx.key = key
				ctx.cert = cert

				server = OpenSSL::SSL::SSLServer.new(server, ctx)

				$log.info("Waiting for splayds on port (SSL): " + @port.to_s)
			else
				$log.info("Waiting for splayds on port: " + @port.to_s)
			end
		rescue => e
			$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			return
		end

		# Protect accept() For example, a bad SSL negotiation makes accept()
		# to raise an exception. Can protect against that and a DOS.
		begin
			loop do
				so = server.accept
				tmpSocket = LLenc.new(so)
       	splaydProtocol = tmpSocket.read()
        if splaydProtocol == "standard" then
				  SplaydProtocol.new(so).run
				elsif splaydProtocol == "grid" then
				  SplaydGridProtocol.new(so).run
				end
			end
		rescue => e
			$log.error(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			sleep 1
			retry
		end
	end
end