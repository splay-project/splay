# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 0) do

  create_table "blacklist_hosts", :force => true do |t|
    t.string "host"
  end

  create_table "job_mandatory_splayds", :force => true do |t|
    t.integer "job_id",    :limit => 11, :null => false
    t.integer "splayd_id", :limit => 11, :null => false
  end

  create_table "jobs", :force => true do |t|
    t.string   "ref",                                                                                            :null => false
    t.integer  "user_id",                   :limit => 11,                                                        :null => false
    t.datetime "created_at"
    t.datetime "scheduled_at"
    t.string   "strict",                    :limit => 0,                                 :default => "FALSE"
    t.string   "name"
    t.string   "description"
    t.string   "localization",              :limit => 2
    t.integer  "distance",                  :limit => 11
    t.decimal  "latitude",                                :precision => 10, :scale => 6
    t.decimal  "longitude",                               :precision => 10, :scale => 6
    t.string   "bits",                      :limit => 0,                                 :default => "32",       :null => false
    t.string   "endianness",                :limit => 0,                                 :default => "little",   :null => false
    t.integer  "max_mem",                   :limit => 11,                                :default => 2097152,    :null => false
    t.integer  "disk_max_size",             :limit => 11,                                :default => 67108864,   :null => false
    t.integer  "disk_max_files",            :limit => 11,                                :default => 512,        :null => false
    t.integer  "disk_max_file_descriptors", :limit => 11,                                :default => 32,         :null => false
    t.integer  "network_max_send",          :limit => 14,                                :default => 134217728,  :null => false
    t.integer  "network_max_receive",       :limit => 14,                                :default => 134217728,  :null => false
    t.integer  "network_max_sockets",       :limit => 11,                                :default => 32,         :null => false
    t.integer  "network_nb_ports",          :limit => 11,                                :default => 1,          :null => false
    t.integer  "network_send_speed",        :limit => 11,                                :default => 51200,      :null => false
    t.integer  "network_receive_speed",     :limit => 11,                                :default => 51200,      :null => false
    t.decimal  "udp_drop_ratio",                          :precision => 3,  :scale => 2, :default => 0.0,        :null => false
    t.text     "code",                                                                                           :null => false
    t.text     "script",                                                                                         :null => false
    t.integer  "nb_splayds",                :limit => 11,                                :default => 1,          :null => false
    t.decimal  "factor",                                  :precision => 3,  :scale => 2, :default => 1.25,       :null => false
    t.string   "splayd_version"
    t.decimal  "max_load",                                :precision => 5,  :scale => 2, :default => 999.99,     :null => false
    t.integer  "min_uptime",                :limit => 11,                                :default => 0,          :null => false
    t.string   "hostmasks"
    t.integer  "max_time",                  :limit => 11,                                :default => 10000
    t.string   "die_free",                  :limit => 0,                                 :default => "TRUE"
    t.string   "keep_files",                :limit => 0,                                 :default => "FALSE"
    t.string   "scheduler",                 :limit => 0,                                 :default => "standard"
    t.text     "scheduler_description"
    t.string   "list_type",                 :limit => 0,                                 :default => "HEAD"
    t.integer  "list_size",                 :limit => 11,                                :default => 0,          :null => false
    t.string   "command"
    t.text     "command_msg"
    t.string   "status",                    :limit => 0,                                 :default => "LOCAL"
    t.integer  "status_time",               :limit => 11,                                                        :null => false
    t.text     "status_msg"
  end

  add_index "jobs", ["ref"], :name => "ref"

  create_table "local_log", :force => true do |t|
    t.integer "splayd_id", :limit => 11, :null => false
    t.integer "job_id",    :limit => 11, :null => false
    t.text    "data"
  end

  add_index "local_log", ["splayd_id"], :name => "splayd_id"
  add_index "local_log", ["job_id"], :name => "job_id"

  create_table "locks", :force => true do |t|
    t.integer "job_reservation", :limit => 11, :default => 0, :null => false
  end

  create_table "splayd_availabilities", :force => true do |t|
    t.integer "splayd_id", :limit => 11,                          :null => false
    t.string  "ip"
    t.string  "status",    :limit => 0,  :default => "AVAILABLE"
    t.integer "time",      :limit => 11,                          :null => false
  end

  create_table "splayd_jobs", :force => true do |t|
    t.integer "splayd_id", :limit => 11,                         :null => false
    t.integer "job_id",    :limit => 11,                         :null => false
    t.string  "status",    :limit => 0,  :default => "RESERVED"
  end

  add_index "splayd_jobs", ["splayd_id"], :name => "splayd_id"

  create_table "splayd_selections", :force => true do |t|
    t.integer "splayd_id",    :limit => 11,                                                      :null => false
    t.integer "job_id",       :limit => 11,                                                      :null => false
    t.string  "selected",     :limit => 0,                                :default => "FALSE"
    t.integer "trace_number", :limit => 11
    t.string  "trace_status", :limit => 0,                                :default => "WAITING"
    t.string  "reset",        :limit => 0,                                :default => "FALSE"
    t.string  "replied",      :limit => 0,                                :default => "FALSE"
    t.decimal "reply_time",                 :precision => 8, :scale => 5
    t.integer "port",         :limit => 11,                                                      :null => false
  end

  add_index "splayd_selections", ["splayd_id"], :name => "splayd_id"
  add_index "splayd_selections", ["job_id"], :name => "job_id"

  create_table "splayds", :force => true do |t|
    t.string   "key",                                                                                              :null => false
    t.string   "ip"
    t.string   "hostname"
    t.string   "session"
    t.string   "name"
    t.string   "country",                   :limit => 2
    t.string   "city"
    t.decimal  "latitude",                                :precision => 10, :scale => 6
    t.decimal  "longitude",                               :precision => 10, :scale => 6
    t.string   "version"
    t.string   "lua_version"
    t.string   "bits",                      :limit => 0,                                 :default => "32"
    t.string   "endianness",                :limit => 0,                                 :default => "little"
    t.string   "os"
    t.string   "full_os"
    t.integer  "start_time",                :limit => 11
    t.decimal  "load_1",                                  :precision => 5,  :scale => 2, :default => 999.99
    t.decimal  "load_5",                                  :precision => 5,  :scale => 2, :default => 999.99
    t.decimal  "load_15",                                 :precision => 5,  :scale => 2, :default => 999.99
    t.integer  "max_number",                :limit => 11
    t.integer  "max_mem",                   :limit => 11
    t.integer  "disk_max_size",             :limit => 11
    t.integer  "disk_max_files",            :limit => 11
    t.integer  "disk_max_file_descriptors", :limit => 11
    t.integer  "network_max_send",          :limit => 14
    t.integer  "network_max_receive",       :limit => 14
    t.integer  "network_max_sockets",       :limit => 11
    t.integer  "network_max_ports",         :limit => 11
    t.integer  "network_send_speed",        :limit => 11
    t.integer  "network_receive_speed",     :limit => 11
    t.string   "command",                   :limit => 0
    t.string   "status",                    :limit => 0,                                 :default => "REGISTERED"
    t.integer  "last_contact_time",         :limit => 11
    t.integer  "user_id",                   :limit => 11,                                :default => 1
    t.datetime "created_at"
  end

  add_index "splayds", ["ip"], :name => "ip"
  add_index "splayds", ["key"], :name => "key"

  create_table "users", :force => true do |t|
    t.string   "login"
    t.string   "email"
    t.string   "crypted_password",          :limit => 40
    t.string   "salt",                      :limit => 40
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "remember_token"
    t.datetime "remember_token_expires_at"
    t.integer  "admin",                     :limit => 11, :default => 0
    t.integer  "demo",                      :limit => 11, :default => 0
  end

end
