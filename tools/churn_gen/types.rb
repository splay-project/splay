class Line
  include Comparable
  attr_reader :time,:action,:churn 
  attr_accessor :original_line
  def initialize (_time_,_action_,_churn_)
    @time,@action,@churn = _time_,_action_,_churn_
  end
  def to_s
    if @time.class == PeriodTiming
      if !@churn
        "#{@time} #{@action}"
      else
        "#{@time} #{@action} #{@churn}"
      end
    else 
      "#{@time} #{@action}"
    end
  end
  # check validity
  # TODO add automatic correction (i.e. remove additional churn request,
  # take the beginning of the period as an instant timing)
  def check_validity
    if @time.class == InstantTiming and @churn
      "Incompatibility between instant timing and additional churn"
    elsif @time.class == PeriodTiming and @action.class == StopAction
      "Incompatibility between period timing and stop action"
    else
      nil
    end
  end
  # optionnal repair
  def repair
    if @time.class == InstantTiming and @churn
      @churn = nil
      "Removing additional churn for this rule"
    end
    if @time.class == PeriodTiming and @action.class == StopAction
      @time = InstantTiming.new(@time.t1)
      "Using the period start as an instant timing"
    end
  end
  # comparator for sorting
  def <=> (other)
    # time
    if @time.t1 != other.time.t1
      @time.t1 <=> other.time.t1
    else
      # same time, actions
      if @action.class.priority != other.action.class.priority
        @action.class.priority <=> other.action.class.priority 
      else
        # same action, instant before start of periods
        if @time.class == InstantTiming and 
          other.time.class == PeriodTiming
          puts "toto"
          -1
        elsif @time.class == PeriodTiming and 
          other.time.class == InstantTiming
          1
        end
        # same action and time type, usage of churn
        if !@churn and other.churn
          1
        elsif @churn and !other.churn
          -1
        else 
          0
        end
      end
    end
  end
  def remove_additional_churn
    @churn = nil
  end
end

class Quantity
  attr_accessor :value, :is_relative
  def initialize (_value_,_is_relative_)
    @value, @is_relative = _value_,_is_relative_
  end
  def to_s
    if !@is_relative
      "#{@value}"
    else
      "#{@value}%"
    end
  end
end

class Timing
end

class InstantTiming < Timing
  attr_reader :t1
  def initialize (_t1_)
    if _t1_ < 0
      STDERR.puts "ERROR: negative time"
      exit -1
    end
    @t1=_t1_
  end
  def to_s
    "at #{@t1} seconds"
  end
end

class PeriodTiming < Timing
  attr_reader :t1
  attr_accessor :t2
  def initialize (_t1_,_t2_)
    if _t1_ < 0 or _t2_ < 0
      STDERR.puts "ERROR: negative time(s)"
      exit -1
    end
    if _t2_ < _t1_
      STDERR.puts "ERROR: bad range"
      exit -1
    end
    if _t2_ == _t1_
      STDERR.puts "ERROR: void range"
      exit -1
    end
    @t1=_t1_
    @t2=_t2_
  end
  def to_s
    "from #{@t1} seconds to #{@t2} seconds"
  end
  def copy
    PeriodTiming.new @t1,@t2
  end
end

class Action
end

class IncreaseAction < Action
  def IncreaseAction.priority
    2
  end
  attr_reader :quantity
  def initialize (_quantity_)
    @quantity=_quantity_
  end
  def to_s
    "increase #{@quantity}"
  end
end

class DecreaseAction < Action
  def DecreaseAction.priority
    2
  end
  attr_accessor :quantity
  def initialize (_quantity_)
    @quantity=_quantity_
  end
  def to_s
    "decrease #{@quantity}"
  end
end

class NullAction < Action
  def NullAction.priority
    3
  end
  def to_s
    "constant"
  end
end

class StopAction < Action
  def StopAction.priority
    4
  end
  def to_s
    "stop"
  end
end

class SetReplacementRatioAction
  def SetReplacementRatioAction.priority
    1
  end
  attr_accessor :quantity
  attr_accessor :real_value
  def initialize (_quantity_)
    @quantity=_quantity_
    if !@quantity.is_relative
      STDERR.puts "BUG the quantity of a SetReplacementRatioAction should only be relative."
      exit 1
    end
    # calculate the real value
    @real_value = (@quantity.value * 1.0)/100.0
  end
  def to_s
    "set replacement ratio to #{@quantity}"
  end
end

class SetMaximumPopulationAction
  def SetMaximumPopulationAction.priority
    1
  end
  attr_accessor :quantity
  def initialize (_quantity_)
    @quantity=_quantity_
    if @quantity.is_relative
      STDERR.puts "BUG the quantity of a SetMaximumPopulationAction cannot be relative."
      exit 1
    end
  end
  def to_s
    "set maximum population to #{@quantity}"
  end
end

class AdditionalChurn 
  attr_accessor :quantity,:is_per_time_unit,:time_ref
  def initialize (_quantity_,_is_per_time_unit_,_time_ref_)
    @quantity=_quantity_
    @is_per_time_unit=_is_per_time_unit_
    @time_ref=_time_ref_
  end
  def to_s
    if is_per_time_unit
      "churn #{@quantity} per #{@time_ref} seconds"
    else
      "churn #{@quantity}"
    end
  end
end
