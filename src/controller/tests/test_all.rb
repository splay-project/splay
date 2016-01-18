require 'minitest/autorun' #not required if done at the top of each test class, here to be sure.
#basic unit tests:
require './test_init_db'
require './test_init_users'
require './test_controller_api'
require './test_json_parse'
require './multifile_tests/test_lua-merger'
require './test_splayd'
#splaynet tests:
require './test_topology_parser'
require './test_min_heap'

#Integration tests
reqire './it_test_register_splayds'



