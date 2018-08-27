require 'minitest/autorun'
require 'allocation_sampler'

class TestAllocationSampler < Minitest::Test
  def test_initialize
    assert ObjectSpace::AllocationSampler.new
  end

  def test_init_with_params
    as = ObjectSpace::AllocationSampler.new(interval: 10)
    assert_equal 10, as.interval
  end

  def test_init_with_location
    iseq = RubyVM::InstructionSequence.new <<-eoruby
    Object.new
    Object.new
    eoruby
    as = ObjectSpace::AllocationSampler.new(interval: 1)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>1, 2=>1}}}, filter(as.result))
  end

  def test_location_same_line
    iseq = RubyVM::InstructionSequence.new <<-eoruby
    10.times { Object.new }
    eoruby
    as = ObjectSpace::AllocationSampler.new(interval: 1)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>10}}}, filter(as.result))
  end

  def test_location_mixed
    iseq = RubyVM::InstructionSequence.new <<-eoruby
    10.times { Object.new }
    Object.new
    eoruby
    as = ObjectSpace::AllocationSampler.new(interval: 1)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>10, 2=>1}}}, filter(as.result))
  end

  def test_location_from_method
    iseq = RubyVM::InstructionSequence.new <<-eoruby
    def foo
      10.times { Object.new }
      Object.new
    end
    foo
    eoruby
    as = ObjectSpace::AllocationSampler.new(interval: 1)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{2=>10, 3=>1}}}, filter(as.result))
  end

  def test_location_larger_interval
    iseq = RubyVM::InstructionSequence.new <<-eom
    100.times { Object.new }
    100.times { Object.new }
    eom
    as = ObjectSpace::AllocationSampler.new(interval: 10)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>10, 2=>10}}}, filter(as.result))
    assert_equal 201, as.allocation_count
  end

  def test_interval_default
    as = ObjectSpace::AllocationSampler.new
    assert_equal 1, as.interval
  end

  def test_two_with_same_type
    as = ObjectSpace::AllocationSampler.new
    as.enable
    Object.new
    Object.new
    as.disable

    assert_equal(2, filter(as.result)[Object.name].values.flat_map(&:values).inject(:+))
  end

  class X
  end

  def test_expands
    as = ObjectSpace::AllocationSampler.new
    as.enable
    500.times do
      Object.new
      X.new
    end
    Object.new
    as.disable

    assert_equal(501, filter(as.result)[Object.name].values.flat_map(&:values).inject(:+))
    assert_equal(500, filter(as.result)[TestAllocationSampler::X.name].values.flat_map(&:values).inject(:+))
  end

  def d; Object.new; end
  def c2; 5.times { d }; end
  def c;  5.times { d }; end
  def b;  50.times { rand < 0.5 ? c : c2 }; end
  def a;  5.times { b }; end

  def test_stack_trace
    as = ObjectSpace::AllocationSampler.new
    as.enable
    a
    as.disable
    result = as.result
    result.each_pair do |class_name, path_hash|
      path_hash.each_pair do |path_name, line_hash|
        line_hash.each_pair do |line, (count, frames)|
          p [class_name, path_name, line, count]
          frames.sort_by { |_, stats| stats[:samples] }.reverse_each do |frame, info|
            p info
            call, total = info[:samples], info[:total_samples]
            printf "% 10d % 8s  % 10d % 8s     %s\n", total, "(%2.1f%%)" % (total*100.0/count), call, "(%2.1f%%)" % (call*100.0/count), info[:name]
          end
        end
      end
    end
  end

  private

  def filter result
    result.each_with_object({}) do |(k,v), a|
      a[k] = v.each_with_object({}) do |(k2,v2), b|
        b[k2] = v2.each_with_object({}) do |(k3, v3), c|
          c[k3] = v3.first
        end
      end
    end
  end
end
