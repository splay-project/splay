#!/usr/bin/env ruby
begin
  require 'treetop'
rescue LoadError
  require 'rubygems'
  gem 'treetop', '< 1.4.9'
  require 'treetop'
end

require 'optparse'
require 'set'

# include files from the same folder
# require_relative 'types' ### this only works with ruby 2
# require_relative 'churn_lang' ### this only works with ruby 2
require File.expand_path(File.join(File.dirname(__FILE__), 'types')) ### this works with ruby 2 and 1.9
require File.expand_path(File.join(File.dirname(__FILE__), 'churn_lang')) ### this works with ruby 2 and 1.9

def fail_with s, err
  STDERR.puts("ERROR: #{s}")
  if err
    STDERR.puts("       this is probably a bug - send a bug report to info@splay-project.org")
  end
  exit 1
end

def warn_with s
  STDERR.puts("WARNING: #{s}")
  if $options[:warning] == false
    STDERR.puts("Warnings are fatal. Exiting. Use option -w to override this setting.")
    exit 2
  end
end

def verbose s
  if $options[:verbose] == true
    STDOUT.puts s
  end
end

# read parameters
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} \n"+
  "\t[-i/--input inputfile]: specifies input churn script file\n"+
  "\t[-o/--output]: specifies output churn trace file\n"+
  "\t[-s/--scheduled]: (optional) specifies output scheduled and disambiguated script file\n"+
  "\t[-n/--no-churn-overlap]: (optional) churn overlap is not allowed during a common period (latest action wins)\n"+
  # "\t[-d/--desc]: specifies optional output peer population evolution "+
  # "file\n"+
  "\t[-h/--help]: prints this help and exits\n"+
  "\t[-v/--verbose]: verbose mode\n"+
  "\t-- at your own risk: --\n"+
  "\t[-m/--minimal_offline_time time]: set a minimal time for offline periods\n"+
  "\t[-c/--minimal_offline_time_allow_creation]: allow creation of nodes to enforce minimal offline time\n"+
  "\t[-a/--minimal_online_time time]: set a minimal time for online periods\n"+
  "\t[-d/--warn-na]: impossible deletes considered as warnings\n"+
  "\t[-w/--warning]: warning are not considered as errors and"+
  " the list of\n\t\taction self-repairs and disambiguate when possible"+
  " (at your own risk)\n"

  opts.on("-i filename", "--input filename", "input script") do |f|
    options[:inputscript] = f
  end
  opts.on("-o filename", "--output filename", "output file") do |f|
    options[:output] = f
  end
  opts.on("-s filename", "--scheduled filename", "output script") do |f|
    options[:scheduled] = f
  end
  opts.on("-n", "--no-churn-overlap") do
    options[:non_overlapping_churn] = true
  end
  # opts.on("-d filename", "--desc filename", 
  # "peer population description") do |f|
  #   options[:desc] = f
  # end
  opts.on("-h", "--help", "Get some help") do
    puts opts.banner
    exit 0
  end
  opts.on("-v", "--verbose", "Verbose mode") do
    options[:verbose] = true
  end
  opts.on("-m time", "--minimal_offline_time time", "minimal offline time") do |t|
    options[:minimal_offline_time] = t.to_i
  end
  opts.on("-c", "--minimal_offline_time_allow_creation", "allow creation of nodes to enforce minimal offline time") do
    options[:minimal_offline_time_allow_creation] = true
  end
  opts.on("-a time", "--minimal_online_time time", "minimal online time") do |t|
    options[:minimal_online_time] = t.to_i
  end
  opts.on("-w", "--warning", "All warnings are not fatal") do
    options[:warning] = true
  end
  opts.on("-d", "--warn-na", "Impossible deletion warnings are not fatal") do
    options[:delete_warning] = true
  end
end.parse!

# check that input and output are properly set
if !options[:inputscript]
  fail_with("Error: input script not specified. Use option -h for help.",false)
end
if !File.exists?(options[:inputscript])
  fail_with("Error: input script #{options[:inputscript]} doesn't exist. Use option -h for help.",false)
end
if !options[:output]
  fail_with("Error: output file not specified. Use option -h for help.",false)
end
if !options[:non_overlapping_churn]
  options[:non_overlapping_churn] = false
end
if  !options[:warning]
  options[:warning] = false
end
if  !options[:delete_warning]
  options[:delete_warning] = false
end
if  !options[:verbose]
  options[:verbose] = false
end

##############################################################################

class ActionList
  attr_reader :list
  attr_accessor :events
  def initialize
    @list=[]
    @events=nil
  end
  def add (l)
    if l.churn != nil
      # create a separate action for the churn
      if l.time.class != PeriodTiming
        fail_with("add. churn with instant timing",true)
      end
      c = Line.new(l.time.copy,NullAction.new,l.churn)
      @list << c
      # remove original churn
      l.remove_additional_churn
    end
    # add only if not constant (the additional churn was treated previously)
    if l.action.class != NullAction
      @list << l
    end
  end
  # this method:
  # 1. sort actions based on their occurence date and priorities (as defined
  #    by the Line class)
  # 2. goes through all actions and normalize additional churn requests:
  #    only one additionnal churn per one period. The behavior is the 
  #    following: the latest period has a higher priority, and replaces 
  #    part of a lower period, which is proportionnaly reduced.
  #    Example: from 10 to 30 keep churn 40%
  #             from 20 to 100 keep churn 100%
  #           are transformed into
  #             from 10 to 20 keep churn 20%
  #             from 20 to 100 keep churn 100%
  def adapt_churn_proportionaly l,t
    # if the initial churn for l was x between t1 and t2, it will be 
    # proportionnaly changed to the corresponding ratio between t1 and t
    l.churn.quantity.value = l.churn.quantity.value *
    (t - l.time.t1) / (l.time.t2 - l.time.t1)
    l.time.t2 = t
  end

  def prepare
    
    # convert churn per time unit to absolute ones
    @list.each do |line|
      if line.churn
        if line.churn.is_per_time_unit
          size = line.churn.quantity.value
          size = size * (line.time.t2 - line.time.t1)
          size = size / line.churn.time_ref
          line.churn.quantity.value = size
          line.churn.is_per_time_unit = false
        end
      end
    end
    
    @list.sort!
    
    # do we want non overlapping churn regions?
    if ($options[:non_overlapping_churn])
      0.upto(@list.length-1) do |index_main|
        a = @list[index_main]
        if a.churn != nil
          # asserts
          if a.action.class != NullAction
            fail_with("during prepare only null actions can contain additional churn",true)
          end
          # find the smallest (if any) time for the next churn action, that is
          # in the current action time range
          min=-1
          (index_main+1).upto(@list.length-1) do |index_sec|
            if @list[index_sec].churn != nil
              if @list[index_sec].time.t1 < list[index_main].time.t2
                min = @list[index_sec].time.t1
                break
              end
            end
          end
          if min != -1
            # change proportionnaly the amount of churn for the reduced period
            adapt_churn_proportionaly @list[index_main],min
          end
        end
        @list.sort!
      end
    end

    # we want churn regions of small size to take into account the evolution of
    # peers to have roughly the same replacement ratio during each part of the
    # period.

    # garder les indexes des lignes remplacees, et la liste des nouveaux a cote, ajouter ensuite, virer ceux qui ne servent plus et retrier
    0.upto(@list.length-1) do |index_main|
      a = @list[index_main]
      if a.churn != nil
        # assert
        if a.churn.is_per_time_unit 
          fail_with "arghh",true
        end

        original_churn = a.churn.quantity.value
        original_time = a.time.t2 - a.time.t1
        original_time_start = a.time.t1
        # divide in set of 2% churn minimum, 10s minimum and at most 20 periods
        periods = 20
        period = original_time / periods
        c = original_churn / periods
        fail = false 
        while period < 10
          # puts "periodes trop courtes"
          periods = periods - 1
          if periods == 0
            fail = true 
          end
          c = original_churn / periods
          period = original_time / periods
          # puts "augmente temps: #{periods} periods of size #{period} seconds et churn #{c}"
        end
        while c < 2
          # puts "trop peu de churn"
          periods = periods - 1
          if periods == 0
            fail = true 
          end
          c = original_churn / periods
          period = original_time / periods
          # puts "augmente churn: #{periods} periods of size #{period} seconds et churn #{c}"
        end        
        if !fail
          # do not modify any churn action if it is not possible (not possible to divide in at least 2 periods)
          r_c = c.floor
          add_c = original_churn - (r_c * periods)
          1.upto(periods) do |i|
            ch = r_c
            if add_c > 0
              ch = ch + 1
              add_c = add_c - 1
            end
            deb = ((original_time / periods) * (i - 1)).ceil
            fin = ((original_time / periods) * i).floor
            # create a new churn event
            nl_time = PeriodTiming.new(original_time_start+deb,original_time_start+fin)
            nl_action = NullAction.new()
            nl_churn_q = Quantity.new(ch,true)
            nl_churn = AdditionalChurn.new(nl_churn_q,false,nil)
            nl = Line.new(nl_time,nl_action,nl_churn)
            # place the new churn event
            if i == 1 
              @list[index_main] = nl
            else
              @list << nl
            end   
          end
        else
          verbose "#{@list[index_main]} can not be split in multiple churn actions"
        end
      end
    end
    @list.sort!
    
    # suppress everything that is after the first end command
    # 1. find the first end command (or its absence)
    implicit_end=-1
    explicit_end=-1
    @list.each do |l|
      if l.action.class == StopAction and explicit_end == -1
        explicit_end = l.time.t1        
      end
      if l.time.class == PeriodTiming
        if l.time.t2 > implicit_end
          implicit_end = l.time.t2
        end
      end
      if l.time.class == InstantTiming
        if l.time.t1 > implicit_end
          implicit_end = l.time.t1
        end
      end
    end

    if explicit_end != -1 
      end_time = explicit_end+1
      EventList.set_end_time_explicit true
    else
      end_time = implicit_end+1
      EventList.set_end_time_explicit false
    end  
    # 2. set end time for the event list generator
    verbose "set end time to #{end_time}"
    EventList.set_end_time end_time
  end

  def process
    # the big job: go through the list of actions and create appropriate
    # peer creation/deletion in the event list
    @list.each do |line|
      verbose "processing line #{line}"
      # process action      
      if line.action.class == SetReplacementRatioAction
        value = line.action.real_value
        @events.add_change_rep_ratio_evt(line.time.t1,value)
      end

      if line.action.class == SetMaximumPopulationAction
        @events.add_change_max_pop_evt(line.time.t1,line.action.quantity)
      end

      if line.action.class == IncreaseAction or line.action.class == DecreaseAction
        size=line.action.quantity.value * 1.0
        if line.action.quantity.is_relative
          # get the size of the peer set at that period
          size = size / 100.0 
          size = size * @events.get_population_at(line.time.t1)          
        end
        size = size.floor

        if line.time.class == InstantTiming      
          if line.action.class == IncreaseAction
            # puts "add increase evt #{line.time.t1}, #{size}"
            @events.add_increase_evt(line.time.t1,size)
          elsif line.action.class == DecreaseAction
            # puts "add decrease evt #{line.time.t1}, #{size}"
            @events.add_decrease_evt(line.time.t1,size)
          end
        else 
          # period timing
          1.upto(size) do |n|
            t = line.time.t1 + ((line.time.t2 - line.time.t1) * (n*1.0)/(size*1.0))
            t = t * 2 ; t = t.floor ; t = t/2
            if line.action.class == IncreaseAction
              # puts " (period from #{line.time.t1} to #{line.time.t2}: add increase evt #{t}"
              @events.add_increase_evt(t,1)
            elsif line.action.class == DecreaseAction
              # puts " (period from #{line.time.t1} to #{line.time.t2}: add decrease evt #{t}"
              @events.add_decrease_evt(t,1)
            end    
          end
        end
      end

      verbose "-> #{@events}"       

      # process churn
      if line.action.class == NullAction and line.churn
        verbose "processing churn #{line.churn} for line #{line}}"        
        size = line.churn.quantity.value * 1.0
        if line.churn.quantity.is_relative
          size = size / 100.0
          # size = size * @events.get_population_at(line.time.t1)
          start_population = @events.get_population_at(line.time.t1)                  
          end_population = @events.get_population_at(line.time.t2)
          mean_population = (start_population + end_population) / 2.0
          size = size * mean_population
        end
        # apply churn
        create_delete=[];
        1.upto(size) do |v|
          t_del=line.time.t1 + rand(line.time.t2 - line.time.t1)
          create_delete << [t_del,false]
          t_cre=line.time.t1 + rand(line.time.t2 - line.time.t1)
          create_delete << [t_cre,true]
        end
        create_delete.sort_by{|x| x[0]}.each do |v|
          if v[1]            
            @events.add_decrease_evt(v[0],1)
          else
            @events.add_increase_evt(v[0],1)
          end
        end            
        verbose "-> #{@events}"      
      end

    end
    # assign peers to all events
    verbose "assign peers to all events"
    @events.assign_peers!
    verbose "-> #{@events}"
  end

  def to_s
    s = ""
    @list.each do |l| 
      s=s+"#{l}\n" 
    end
    s  
  end

  def write_to_file filename
    File.open(filename,"w") do |f|
      f.write(to_s())
    end
  end
end

class Event
  attr_accessor   :time,:peer
  attr_accessor :prev,:next # doubly linked list
  attr_accessor :skipped
  def initialize (n, t)
    @peer, @time = n,t
    @skipped = false
  end
  def set_pointers (p,n)
    @prev, @next = p,n
  end
end
class EventAddPeer < Event
  attr_accessor :is_creation
  def to_s
    "#{@time}:+p#{@peer}"
  end
end
class EventRemovePeer < Event
  def to_s
    "#{@time}:-p#{@peer}"
  end
end
class EventBegin < Event 
  def to_s
    "#{@time}:begin"
  end
end
class EventEnd < Event
  def to_s
    "#{@time}:stop"
  end
end
class EventChangeRepRatio < Event
  attr_accessor :value
  def to_s
    "#{@time}:change_rep_ratio(#{@value})"
  end
end
class EventChangeMaxPopulation < Event
  attr_accessor :value
  def to_s
    "#{@time}:change_max_population(#{@value})"
  end
end

class PrintableSet < Set
  def rand_elt
    tmp_a=to_a
    tmp_a[rand(tmp_a.length)]
  end
  def to_s
    r=""
    each do |e|
      r+=" #{e}"
    end
    r
  end
end

class EventList
  def initialize
    @begin=EventBegin.new(-1,0)
    @end=EventEnd.new(nil,@@end_time) # end time unspecified for the moment
    @begin.set_pointers(nil,@end)
    @end.set_pointers(@begin,nil)
    @current=@begin
    @population=0
  end

  private

  def reward_simulate 
    # un-simulate current
    if @current.class == EventAddPeer
      @population = @population - 1
    elsif @current.class == EventRemovePeer
      if @current.skipped == false
        @population = @population + 1
      end
    end
  end
  def forward_simulate
    # simulate current
    if @current.class == EventAddPeer
      @population = @population + 1
    elsif @current.class == EventRemovePeer
      if @population > 0
        @population = @population - 1
        @current.skipped = true
      end
    end
  end

  def go_to t
    if t < 0 
      fail_with("#{__LINE__} -- go_to can not go to time #{t}",true)
    end
    # forward
    if @current.time > t
      # rewind until the first with same of smaller time 
      while @current.time > t
        reward_simulate
        @current = @current.prev             
      end  
    else
      # forward (if needed til the end of the same time period)      
      while (@current.class != EventEnd) and (@current.next.time <= t)
        @current = @current.next
        forward_simulate
      end      
    end
  end

  def add_at_current evt
    if @current.class != EventEnd
      evt.next = @current.next
      evt.prev = @current
      @current.next.prev = evt
      @current.next = evt    
      @current = evt
      forward_simulate
    end
  end

  public
  def write_to_file filename
    i=@begin
    total=Hash.new # contains an array for each peer
    while (i != @end)
      if i.class == EventRemovePeer or i.class == EventAddPeer
        if !total[i.peer]
          total[i.peer] = []
        end
        total[i.peer] << i.time      
      end
      i=i.next
    end
    # open output file
    File.open(filename,"w") do |f|
      total.sort_by{|key,value| key}.each do |key,value|    
        s = ""
        alive = false
        value.each do |v|
          s = s+" #{v}"
          alive = !alive
        end
        if alive and @@end_time_explicit
          s = s+" #{@@end_time}"
        end  
        f.puts "#{s}"
      end
    end
  end

  def EventList.set_end_time_explicit t
    @@end_time_explicit = t
  end
  def EventList.set_end_time t
    @@end_time = t
  end
  def get_population_at(t)
    go_to t
    @population
  end
  def add_increase_evt t,n
    go_to t
    1.upto(n) do |i|
      evt = EventAddPeer.new(nil, t)
      evt.is_creation = nil # will be decided upon resolution
      add_at_current evt
    end
  end
  def add_decrease_evt t,n
    go_to t
    1.upto(n) do |i|
      evt = EventRemovePeer.new(nil, t)
      add_at_current evt
    end
  end
  def add_change_rep_ratio_evt t,v
    go_to t
    evt = EventChangeRepRatio.new(nil, t)
    evt.value = v
    add_at_current evt
  end
  def add_change_max_pop_evt t,v
    go_to t
    evt = EventChangeMaxPopulation.new(nil, t)
    evt.value = v
    add_at_current evt
  end

  def assign_peers!
    # finalization: go through all events and assign the peers using alive and dead sets
    @current=@begin
    @population=0
    max_id=0
    alive=PrintableSet.new
    dead=PrintableSet.new
    while @current.class != EventEnd
      if @current.class == EventChangeRepRatio
        $prob_creation = @current.value        
      end
      if @current.class == EventChangeMaxPopulation
        $max_population = @current.value.value
      end

      if @current.class == EventAddPeer
        prob = rand
        peer = nil
        max_pop_reached = false
        
        is_creation = (prob < $prob_creation or dead.size == 0)      
                      
        if @population+1 > $max_population and is_creation
          # max population reached, try to use the dead peers if possible
          max_pop_reached = true
          is_creation = false
          # puts "falling back to using a dead one / instead of creating one"
          if dead.size == 0 
            fail_with "Max population is not enough to satisfy some increase action: #{@current}", false
          end
        end

        if !is_creation        
          # if we need to have peers offline for at least a period, then
          # we need to enforce it
          if $options[:minimal_offline_time]            
            ok_peers = PrintableSet.new
            dead.each do |elt|
              # include in the set iff the peer was offline for at least the minimal period
              # puts "-- examine peer #{elt}: last time offline=#{$last_time_offline[elt]}, current time = #{@current.time} and min time=#{$options[:minimal_offline_time]}"
              if $last_time_offline[elt] <= @current.time-$options[:minimal_offline_time]
                ok_peers << elt                
                # puts "time is now #{@current.time} and the time of the candidate is #{$last_time_offline[elt]}"
              end
            end
            # ok_peers = dead.select{|x| !$last_time_offline[x] or ($last_time_offline[x] <= @current.time-$options[:minimal_offline_time])}
            if ok_peers.size == 0
              if $options[:minimal_offline_time_allow_creation]
                is_creation=true
              else
                # puts "unable to respect the minimal_offline_time (time is #{@current.time})-> using a the peer that was offline the latest"
                min_time=1000*1000*1000
                dead.each do |elt|
                  if $last_time_offline[elt] < min_time
                    peer = elt
                    min_time = $last_time_offline[elt]
                  end
                end
                # puts "the best choice is peer #{peer} with #{$last_time_offline[peer]}"
              end
            else
              peer = ok_peers.rand_elt              
            end
          end
          # otherwise, or if we do not find such a peer, we pick a random one.
          if !peer
            peer = dead.rand_elt
            # puts " ---> random peer used is #{peer} with , with #{$last_time_offline[peer]}"
          end
        end
                
        if is_creation    
          # create a new peer
          max_id = max_id + 1
          peer = max_id
        end
        
        @current.peer = peer
        @current.is_creation = is_creation
        # safety check and addition to alive set
        ok = alive.add?(@current.peer)
        if !ok
          fail_with("#{__LINE__} -- peer #{@current.peer} should not have been in the alive set",true)
        end
        # remove from dead set if it is not a creation
        if !@current.is_creation
          ok = dead.delete?(@current.peer)
          if !ok
            fail_with("#{__LINE__} -- peer #{@current.peer} should have been in the dead set",true)
          end
        end
        # take into account the new peer in the population size
        @population = @population + 1   
        # track information for minimal online time enforcement
        if $options[:minimal_online_time]
          if $last_time_online == nil
            $last_time_online=Hash.new
          end
          $last_time_online[@current.peer]=@current.time
        end
      elsif @current.class == EventRemovePeer
        if @population > 0          
          peer = alive.rand_elt
          
          # if we need to have peers offline for at least a period, then
          # we need to enforce it
          if $options[:minimal_online_time]
            ok_peers = PrintableSet.new
            alive.each do |elt|
              # include in the set iff the peer was offline for at least the minimal period
              if $last_time_online[elt] <= @current.time-$options[:minimal_online_time]
                ok_peers << elt
              end
            end
            if ok_peers.size == 0
              # puts "unable to respect the minimal_online_time -> using the peer that was online the latest"
              min_time=1000*1000*1000
              alive.each do |elt|
                if $last_time_online[elt] < min_time
                  peer = elt
                  min_time = $last_time_online[elt]
                end
              end
            else
              # force the use of one that respect the constraint
              peer = ok_peers.rand_elt
            end
          end
          
          @current.peer = peer
          
          # remove from alive set
          ok = alive.delete?(@current.peer)
          if !ok 
            fail_with("#{__LINE__} -- bug, peer #{@current.peer} should have been in the alive set",true)
          end
          # add to dead set
          ok = dead.add?(@current.peer)
          if !ok
            fail_with("#{__LINE__} -- bug, peer #{@current.peer} should not have been in the dead set",true)
          end
          # update population
          @population = @population - 1
          # track information for minimal offline time enforcement
          if $options[:minimal_offline_time]
            if $last_time_offline == nil
              $last_time_offline=Hash.new
            end
            $last_time_offline[@current.peer]=@current.time
          end
        else
          # TODO: if it is fatal 
          msg = "event #{@current} ignored -- no peer alive at time #{@current.time}"
          if options[:delete_warning] 
            warn_with(msg) 
          else 
            fail_with(msg) 
          end            
        end     
      end
      @current = @current.next        
    end
  end

  def to_s
    s=""
    i=@begin
    while i != @end
      s+="#{i} "
      i=i.next
    end
    s+"#{i}"
  end  
end

class ChurnGen
  def initialize (_parser_)
    @parser=_parser_
  end

  def main
    # structures
    actions = ActionList.new

    # set defaults
    $prob_creation = 0.2
    $max_population = 10000000

    # todo: add a mean to explicitely set the min number of seconds for which
    # a peer has to stay offline after being killed -- or a distribution of
    # this time over all peers.

    # parse
    l=0
    File.open($options[:inputscript]).each do |line|
      l=l+1
      line = line.rstrip
      e = @parser.parse(line)
      if !e
        warn_with "syntax error in line #{l} (#{line}): #{@parser.failure_reason}. Ignoring line."
      elsif e.desc != nil
        desc = e.desc
        if desc.check_validity != nil
          warn_with line+desc
          warn_with line+"** repair ** #{desc.repair}"
          warn_with "corrected: #{desc}"
        end
        e.desc.original_line = line
        actions.add(e.desc)
      else # comment
        # puts "Ignored comment: #{line}"
      end
    end

    verbose ""
    verbose "Content of list: \n#{actions}"
    verbose ""
    actions.prepare
    actions.events = EventList.new
    verbose "Content of sorted list:\n#{actions}"
    verbose ""
    verbose "--- Processing ---"

    if $options[:scheduled]
      verbose "--- Writing scheduled action list to #{$options[:scheduled]}"
      actions.write_to_file $options[:scheduled]
    end

    actions.process

    verbose ""
    verbose "--- Result ---"
    verbose "#{actions.events}"

    verbose ""
    verbose "--- Writing to file #{$options[:output]}"

    actions.events.write_to_file $options[:output]
  end
end

$options=options
c = ChurnGen.new(ChurnLangParser.new)
c.main
