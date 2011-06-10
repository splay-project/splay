class Blacklistd
	@@blacklist_interval = Config::BlacklistInterval
	def self.run()
		return Thread.new do
			main
		end
	end

	def self.main
		begin
			$log.info(">>> Splay Controller Blacklist Daemon")
			bl = []
			while sleep(@@blacklist_interval)
				new_bl = []
				if Config::PublicIP
					new_bl << Config::PublicIP
				end
				$db.select_all "SELECT host FROM blacklist_hosts" do |row|
					new_bl << row[0]
				end

				if bl != new_bl then
					bl = new_bl

					# If the splayd is UNAVAILABLE or RESET, it will needs to
					# reconnect to be AVAILABLE and so, will already receive the
					# latest blacklist.
					$db.select_all "SELECT * FROM splayds WHERE status='AVAILABLE'" do |splayd|
						action = $db.select_one "SELECT * FROM actions WHERE
								splayd_id='#{splayd['id']}' AND
								command='BLACKLIST'"
						if not action
							$db.do "INSERT INTO actions SET
									splayd_id='#{splayd['id']}',
									command='BLACKLIST',
									data='#{bl.to_json}'"
						else
							$db.do "UPDATE actions SET
									data='#{bl.to_json}'
									WHERE
									splayd_id='#{splayd['id']}' AND
									command='BLACKLIST'"
						end
					end
				end
			end
		rescue => e
			$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
		end
	end
end
