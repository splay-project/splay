require "minitest/autorun"
require "algorithms" #File.expand_path(File.join(File.dirname(__FILE__), 'heap'))
include Containers

class TestMinHeap < Minitest::Test
  def test_1  
    minheap = MinHeap.new([1, 1, 3, 4])
    assert_equal(4,minheap.size)
    assert_equal(1,minheap.pop) #=> 2
  end
end