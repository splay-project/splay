require "test/unit"
require "algorithms" #File.expand_path(File.join(File.dirname(__FILE__), 'heap'))
include Containers

class TestMinHeap < Test::Unit::TestCase
  def test_1  
    minheap = MinHeap.new([1, 1, 3, 4])
    puts minheap.size
    assert_equal(2,minheap.pop) #=> 2
  end
end