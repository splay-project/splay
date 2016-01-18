## Parser for ModelNet Topology Descriptor
## <topology>
##   <vertices>
##     <vertex int_idx="1" role="gateway" />
##     <vertex int_idx="2" role="virtnode" int_vn="0" />
##     </vertices>
##   <edges>
##     <edge int_dst="1" int_src="2" int_idx="0" int_len="300" specs="client-stub" int_delayms="1" />
##     <edge int_dst="2" int_src="1" int_idx="1" int_len="300" specs="client-stub" dbl_kbps="768" />
##     <edge int_dst="1" int_src="5" int_idx="0" int_len="20" specs="stub-stub" />
##   </edges>
##   <specs>
##     <client-stub dbl_plr="0" dbl_kbps="64" int_delayms="100" int_qlen="10" />
##     <stub-stub dbl_plr="0" dbl_kbps="1000" int_delayms="20" int_qlen="10" />
##   </specs>
## </topology>

require 'nokogiri' ##to quickly read XML. gems install nokogiri
#require 'dijkstra'
require File.expand_path(File.join(File.dirname(__FILE__), 'dijkstra'))

class TopologyParser  
  
  def initialize
    #the default values, as stored in the XML file in the specs block
    @defaults=Hash.new
    @virtual_nodes=Hash.new
    @middle_nodes=Hash.new
    @gr = Graph.new
  end
  
  def defaults() return @defaults end
  def virtualnodes() return @virtual_nodes end
  def middlenodes() return @middle_nodes end
      
  ##return the built graph
  def parse(input,from_file=true)
    #print(input)
    if from_file then
      xml=File.open(input,'r')
      graph = Nokogiri::XML(xml)
      xml.close()
    else
      #puts("Current Ruby  version: "+RUBY_VERSION)
      #puts("Parsing topology file [raw]:"+input)      
      #puts("Parsing topology file [class]:"+input.class.to_s)
      #puts("Parsing topology file:"+input[2..(input.length-3)].chomp)
      
      if RUBY_VERSION=="1.9.2" then
         input.delete!"\n","\t","\\"
        graph = Nokogiri::XML((input[2..(input.length-3)]))
      else
        graph = Nokogiri::XML(input)        
      end  
    end
    
    ## full traversal here
    ## check if it's more efficient with XPath query
    graph.root.traverse do |elem|
      if elem.name=="specs" then        
        elem.traverse do |s| 
          # <client-stub dbl_plr="0" dbl_kbps="64" int_delayms="100" int_qlen="10" />
          # <stub-stub dbl_plr="0" dbl_kbps="1000" int_delayms="20" int_qlen="10" />
            if s.name=="client-stub"or s.name=="stub-stub" or s.name=="transit-transit" or s.name="stub-transit" or s.name="client-client" then              
                @defaults[s.name]=Hash.new()
                if s['dbl_plr']     then  @defaults[s.name]['dbl_plr']    =s['dbl_plr'].to_i end
                if s['dbl_kbps']    then  @defaults[s.name]['dbl_kbps']   =s['dbl_kbps'].to_i end 
                if s['int_delayms'] then  @defaults[s.name]['int_delayms']=s['int_delayms'].to_i end 
                if s['int_qlen']    then  @defaults[s.name]['int_qlen']   =s['int_qlen'].to_i end       
            end 
        end        
      end
    end
    
    #The topology is expected to have directed edges, but the XML can be incomplete.
    #A completion step is added at the end of the parsing to add the missing edges.
    added_edges=Hash.new
    
    graph.root.traverse do |elem|
      
      # <edge int_dst="1" int_src="2" int_idx="0" int_len="300" specs="client-stub" int_delayms="1" dbl_kbps="768"  />
      if elem.name == "edge" then
        edge_attribs=Hash.new #will store fields used by dijkstra, decorates edges
        src=nil
        dst=nil
        elem.traverse do |e| 
            src=e['int_src']
            dst=e['int_dst']
            #puts e['int_dst']+" -> "+e['int_src']+" "+e['int_len']              
            edge_spec=e['specs']
            
            ##use defaults, then overwrite if value is given
            edge_attribs['int_delayms'] = @defaults[edge_spec]['int_delayms']
            if e['int_delayms'] != nil then
              edge_attribs['int_delayms'] = e['int_delayms'].to_i                
            end
            #  edge_attribs['int_delayms'] = @defaults[edge_spec]['int_delayms']
            #end
            edge_attribs['dbl_kbps'] = @defaults[edge_spec]['dbl_kbps']
            if e['dbl_kbps'] !=nil then
              edge_attribs['dbl_kbps'] = e['dbl_kbps'].to_i
            end
        end
        
        @gr.add_edge(src,dst,edge_attribs)
        added_edges[[src,dst]]=edge_attribs
        
        
        #<vertex int_idx="2" role="virtnode" int_vn="1" />  
      elsif elem.name == "vertex" then
         elem.traverse do |e|
           role=e['role']
           if role=="virtnode" then
              @virtual_nodes[e['int_vn']]=e['int_idx']
           else
              @middle_nodes[e['int_idx']]=e['int_idx'] ##Gateway nodes do not ship int_vn number, using int_idx
           end
         end
      end
    end
    if $log then
      $log.info("Topology parsing complete.")
    end
    #complete the graph with the missing edges if any
    added_edges.each{|key,value|
      #key.each{|a| puts a}
      #puts key[0],key[1],value.to_s
      
      if added_edges[[key[1],key[0]]]==nil then
        #add missing edge using same attribs as existing one (should use defaults instead)
        @gr.add_edge(key[1],key[0],added_edges[[key[0],key[1]]])
      end
    }
    if $log then
      $log.info("Topology completion complete.")
    end
    return @gr
    
  end
  
end
