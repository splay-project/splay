require "minitest/autorun"
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/topology_parser'))
require 'json' #gems install json

class TestTopologyParser < Minitest::Test

  def setup
    @parser= TopologyParser.new()
    refute_nil(@parser)
  end

  def test_graph_0
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/test_graph_0.xml')))   
    refute_nil(graph,"Graph is nil")
    defs = @parser.defaults()
    refute_nil(defs,"Default is nil, could not read <specs/> section? ")
    vn=@parser.virtualnodes()
    refute_nil(vn)
    assert_equal(vn.keys.size,2)
    mn=@parser.middlenodes()
    refute_nil(mn)
    assert_equal(mn.keys.size,1)
    
    assert_equal(20,graph.link_latency("g","2"))

    graph.dijkstra "2"
    assert_equal(320,graph.path_latency(graph.path("2","1")))
    
    assert_equal(300,graph.link_latency("1","g"))
    graph.dijkstra "1"
    assert_equal(320,graph.path_latency(graph.path("1","2")))
    
    
    
    path_1_2 = graph.path("1","2")
    refute_nil(path_1_2)
    #puts path_1_2.to_s
    assert_equal(3,path_1_2.size)
    assert_equal("1",path_1_2[0])
    assert_equal("g",path_1_2[1])
    assert_equal("2",path_1_2[2])  
    assert_equal(256,graph.link_kbps("g","2"))
    assert_equal(64,graph.link_kbps("1","g"))
    
    assert_equal(320, graph.path_latency(path_1_2)) #101 because 100+1, 1>g is fast, g>2 is slow
    assert_equal(64,  graph.path_kbps(path_1_2)) #should be the MIN between the values reported by nodes and edges along the path
    
  end

  def test_graph_1
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/test_graph_1.xml')))
    refute_nil(graph,"Graph is nil")
    defs = @parser.defaults()
    refute_nil(defs,"Default is nil, could not read <specs/> section? ")
    #graph.shortest_paths("1")
    vn=@parser.virtualnodes()
    refute_nil(vn)
    assert_equal(vn.keys.size,2)
    mn=@parser.middlenodes()
    refute_nil(mn)
    assert_equal(mn.keys.size,1)
  end
  
  def test_graph_2
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/test_graph_2.xml')))
    refute_nil(graph,"Graph is nil")
    defs = @parser.defaults()
    refute_nil(defs,"Default is nil, could not read <specs/> section? ")
    #graph.shortest_paths("1")
    vn=@parser.virtualnodes()
    refute_nil(vn)
    assert_equal(4,vn.keys.size)
    mn=@parser.middlenodes()
    refute_nil(mn)
    assert_equal(2,mn.keys.size)
    graph.dijkstra "0"
    path_0_5 = graph.path("0","5")
    refute_nil(path_0_5)
    #path_0_5.each{|hop| puts hop}
    
    assert_equal(5,path_0_5.length)
    assert_equal("0",path_0_5[0])
    assert_equal("1",path_0_5[1])
    assert_equal("2",path_0_5[2])
    assert_equal("4",path_0_5[3])
    assert_equal("5",path_0_5[4])
    
    assert_equal(231, graph.path_latency(path_0_5)) 
    assert_equal(1024,  graph.path_kbps(path_0_5))

  end
  
  
  def test_graph_3
    
    input = <<-END_XML
    <?xml version="1.0" encoding="ISO-8859-1"?>
    <topology>
    	<vertices>
    		<vertex int_idx="0" role="virtnode" int_vn="1" />
    		<vertex int_idx="1" role="gateway" />
    		<vertex int_idx="2" role="virtnode" int_vn="2" />
    		<vertex int_idx="3" role="virtnode" int_vn="3" />
    		<vertex int_idx="4" role="gateway" />
    		<vertex int_idx="5" role="virtnode" int_vn="4" />
    	</vertices>
    	<edges>
    		<edge int_src="0" int_dst="1" int_idx="0" int_len="300" specs="client-stub" int_delayms="1" dbl_kbps="2048" />
    		<edge int_src="1" int_dst="2" int_idx="1" int_len="300" specs="stub-stub" int_delayms="200" />
    		<edge int_src="1" int_dst="3" int_idx="2" int_len="300" specs="stub-stub" int_delayms="200" />
    		<edge int_src="2" int_dst="4" int_idx="3" int_len="30" specs="stub-stub" />
    		<edge int_src="3" int_dst="4" int_idx="4" int_len="30" specs="stub-stub" int_delayms="250" />
    		<edge int_src="4" int_dst="5" int_idx="5" int_len="30" specs="client-stub" int_delayms="10" dbl_kbps="1024"/>
    	</edges>
    	<specs>
    		<client-stub dbl_plr="0" dbl_kbps="64" int_delayms="100" int_qlen="10" />
    		<stub-stub dbl_plr="0" dbl_kbps="4048" int_delayms="20" int_qlen="10" />
    	</specs>
    </topology>
    END_XML
    
    graph = @parser.parse(input,false) #false to specify input is not on a file
    refute_nil(graph,"Graph is nil")
    defs = @parser.defaults()
    refute_nil(defs,"Default is nil, could not read <specs/> section? ")
    #graph.shortest_paths("1")
    vn=@parser.virtualnodes()
    refute_nil(vn)
    assert_equal(4,vn.keys.size)
    mn=@parser.middlenodes()
    refute_nil(mn)
    assert_equal(2,mn.keys.size)
    graph.dijkstra "0"
    path_0_5 = graph.path("0","5")
    refute_nil(path_0_5)
    #path_0_5.each{|hop| puts hop}
    
    assert_equal(5,path_0_5.length)
    assert_equal("0",path_0_5[0])
    assert_equal("1",path_0_5[1])
    assert_equal("2",path_0_5[2])
    assert_equal("4",path_0_5[3])
    assert_equal("5",path_0_5[4])
    
    assert_equal(231, graph.path_latency(path_0_5)) 
    assert_equal(1024,  graph.path_kbps(path_0_5))
    
    #vn.each_key{|node_x|    
    #  vn.each_key{|node_y|
    #    if node_x!=node_y then
    #      puts "#{node_x} to #{node_y} :#{graph.path_latency(graph.path(node_x,node_y))}"
    #    end
    #  }   
    #  graph.shortest_paths(node_x)
    #}
  end
  
  def test_graph_4
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/test_graph_1.xml')))
    
    vn=@parser.virtualnodes()
    assert_equal(2,vn.keys.size)
    
    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)
    #should have 1 entry per VN
    assert_equal(2,splay_topo.keys.size)
    #print JSON.unparse splay_topo
    #assert_equal('{"1":{"2":[500,768]},"2":{"1":[500,64]}}', JSON.unparse(splay_topo))
  end
  
  def test_graph_5_malformed
    input="<!-- simple graph: 1-g-2 -->\n<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<topology>\n\t<vertices>\n\t\t<vertex int_idx=\"0\" role=\"gateway\" />\n\t\t<vertex int_idx=\"1\" role=\"virtnode\" int_vn=\"1\" />\n\t\t<vertex int_idx=\"2\" role=\"virtnode\" int_vn=\"2\" />\n\t</vertices>\n\t<edges>\n\t\t<edge int_src=\"1\" int_dst=\"g\" int_idx=\"1\" int_len=\"300\" specs=\"client-stub\" dbl_kbps=\"768\" />\n\t\t<edge int_src=\"g\" int_dst=\"2\" int_idx=\"0\" int_len=\"300\" specs=\"client-stub\" int_delayms=\"1\" />\n\t</edges>\n\t<specs >\n\t\t<client-stub dbl_plr=\"0\" dbl_kbps=\"64\" int_delayms=\"100\" int_qlen=\"10\" />\n\t\t<stub-stub dbl_plr=\"0\" dbl_kbps=\"1000\" int_delayms=\"20\" int_qlen=\"10\" />\n\t</specs>\n</topology>\n"
    input.delete!"\n","\t","\\"
    #puts "Cleaned input:\n"+ input
    graph = Nokogiri::XML(input)
    refute_nil(graph.root)
  end
  def test_graph_6
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/mini_pl.xml')))
    
    vn=@parser.virtualnodes()
    assert_equal(2,vn.keys.size)
    graph.dijkstra "1"
    path_1_3=graph.path("1","3")
    
    #path_1_3.each{|p| puts p}
    #puts "path_1_3 latency: #{graph.path_latency(path_1_3)}"
    assert_equal(284,graph.path_latency(path_1_3))
    graph.dijkstra "3"
    path_3_1=graph.path("3","1")
    #puts" Path 3>1:"
    #path_3_1.each{|p| puts p}
    assert_equal(9659,graph.path_latency(path_3_1))
     
    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)
    #should have 1 entry per VN
    assert_equal(2,splay_topo.keys.size)
    ##print "Going to encode splay_top to json.."
    #print JSON.unparse splay_topo
    #assert_equal('{"1":{"3":[284,64]},"3":{"1":[9659,64]}}', JSON.unparse(splay_topo))
  end
  def test_graph_7
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/planetlab.xml')))    
    vn=@parser.virtualnodes()
    assert_equal(62,vn.keys.size)
    graph.dijkstra "18"
    path=graph.path("18","55")
    #path.each{|p| puts p}
    #puts "path latency: #{graph.path_latency(path)}"

    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)

    #print "Going to encode splay_top to json.."
    #print JSON.unparse splay_topo
    #assert_equal('{"1":{"2":[100,768]},"2":{"1":[100,768]}}', JSON.unparse(splay_topo))
  end

  def test_graph_8
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/stacktoodeep.xml')))    
    vn=@parser.virtualnodes()
    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)

  end
  def test_graph_9
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/pl_14nodes.xml')))    
    vn=@parser.virtualnodes()
    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)
  end
  def test_graph_10
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/13nodes_lan_100ms.xml')))    
    vn=@parser.virtualnodes()
    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)
    (1..13).each { |i| 
      graph.dijkstra i.to_s
      (1..13).each {|j|
      if i!=j then
        #puts "#{i} #{j}"
        path=graph.path(i.to_s,j.to_s)
        assert_equal(100,graph.path_latency(path))
      end
      } 
    }
    
  end
  
  def test_graph_11
    graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/modelnet_bandwidth_4nodes.xml')))    
    vn=@parser.virtualnodes()
    assert_equal(4,vn.keys.size)
    splay_topo=graph.splay_topology(vn)
    refute_nil(splay_topo)
    graph.dijkstra "1"
    path=graph.path("1","5")
    assert_equal(100,graph.path_latency(path))
    assert_equal(512,graph.path_kbps(path))
    
    
    path_1_4=graph.path("1","4")
    path_hops=graph.path_hops_kbps(path_1_4)
    refute_nil(path_hops)
    #path_hops.each{|i| puts "#{i}"}
  end
  
  
  def test_graph_12
     graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/iperf_multistream_topology.xml')))      
     vn=@parser.virtualnodes()
     assert_equal(10,vn.keys.size)
     splay_topo=graph.splay_topology(vn)
     refute_nil(splay_topo)
     graph.dijkstra "1"
     path=graph.path("1","6")
     assert_equal(0,graph.path_latency(path))
     assert_equal(10240,graph.path_kbps(path))
   end
  
   #testcases 13,14 introduced after a StackTooDeep error due to wrong links
   def test_graph_13
     graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/butterfly_100.xml')))     
     vn=@parser.virtualnodes()
     splay_topo=graph.splay_topology(vn)
     refute_nil(splay_topo)
   end
   def test_graph_14
     graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/butterfly_200.xml')))     
     vn=@parser.virtualnodes()
     splay_topo=graph.splay_topology(vn)
     refute_nil(splay_topo)
   end
   
   #def test_graph_bgp_1
   #  graph = @parser.parse('topologies/bgp_4000nodes_200clients_25stubs.xml')
   #  vn=@parser.virtualnodes()
   #  #vn.each_key{|node_x|    
   #  #  vn.each_key{|node_y|
   #  #    if node_x!=node_y then
   #  #      puts "#{node_x} to #{node_y} :#{graph.path_latency(graph.path(node_x,node_y))}"
   #  #    end
   #  #  }   
   #  # # graph.shortest_paths(node_x)
   #  #}
   #  splay_topo=graph.splay_topology(vn)
   #  refute_nil(splay_topo)
   #end
   
   def test_graph15
      graph = @parser.parse( File.expand_path(File.join(File.dirname(__FILE__), 'topologies/unfair.xml')))     
      vn=@parser.virtualnodes()
      splay_topo=graph.splay_topology(vn)
      refute_nil(splay_topo)
      graph.dijkstra "1"
      path=graph.path("1","4")
      assert_equal(25,graph.path_latency(path))
      path=graph.path("1","5")
      assert_equal(50,graph.path_latency(path))
      path=graph.path("1","6")
      assert_equal(120,graph.path_latency(path))
    end
end
