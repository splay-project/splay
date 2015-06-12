require 'lua-merger.rb'
require "test/unit"
require 'tmpdir' 
require 'tempfile'

require "base64"

class TestLuaMerger < Test::Unit::TestCase

# input A:	events.run()
# input B:	events.run()
# output C:	events.run()
def test_multiple_run_methods1()
	tar_file = File.open("chunk-run1.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	out_file = File.open("chunk-run1.out", "r")
	expected_output = out_file.read
	assert_equal(expected_output, output)
end

# input  A:	events.thread(), events.run()
# input  B:	events.run()
# output C:	events.thread(), events.thread(), events.run()
def test_multiple_run_methods2()
	tar_file = File.open("chunk-run2.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	out_file = File.open("chunk-run2.out", "r")
	expected_output = out_file.read
	assert_equal(expected_output, output)
end

# input  A:	events.thread(), events.run()
# input  B:	events.thread(), events.run()
# output C:	events.thread(), events.thread(), events.run()
def test_multiple_run_methods3()
	tar_file = File.open("chunk-run3.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	out_file = File.open("chunk-run3.out", "r")
	expected_output = out_file.read
	assert_equal(expected_output, output)
end

# input  A:	require"splay.events"
# input  B:	require"splay.events"
# output C:	require"splay.events"
def test_require1
	tar_file = File.open("chunk-require1.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	out_file = File.open("chunk-require1.out", "r")
	expected_output = out_file.read
	assert_equal(expected_output, output)
end

# input  A:	require"splay.events"
# input  B:	local events = require"splay.events"
# output C:	error message!
def test_require2
	tar_file = File.open("chunk-require2.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	expected_output = "module splay.events is allocated to two different variables: nil and events"
	assert_equal(expected_output, ret['error'], ret['error'])
end

# input  A:	local x = require"splay.events"
# input  B:	local y = require"splay.events"
# output C:	error message!
def test_require3
	tar_file = File.open("chunk-require3.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	expected_output = "module splay.events is allocated to two different variables: x and y"
	assert_equal(expected_output, ret['error'], ret['error'])
end

# input  A:	function chunky()
# input  B:	function chunky()
# output C:	function chunky(), function chunky_()
def test_functions
	tar_file = File.open("chunk-functions.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	out_file = File.open("chunk-functions.out", "r")
	expected_output = out_file.read
	assert_equal(expected_output, output, "Functions test failed!")
end

# input  A:	local chunk_number = 1
# input  B:	local chunk_number = 2
# output C:	local chunk_number = 1, local chunk_number_ = 2 and also replaces occurrences
def test_variables
	tar_file = File.open("chunk-variables.tar.gz","rb")
	content = tar_file.read
	encoded_content = Base64.encode64(content)
	ret = Hash.new
	output, ret = LuaMerger.new.merge_lua_files(encoded_content, ret)

	out_file = File.open("chunk-variables.out", "r")
	expected_output = out_file.read
	assert_equal(expected_output, output, "Variables test failed!")
end

end
