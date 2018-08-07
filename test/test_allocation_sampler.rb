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
    as = ObjectSpace::AllocationSampler.new(interval: 1, location: true)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>1, 2=>1}}}, as.result)
  end

  def test_location_same_line
    iseq = RubyVM::InstructionSequence.new <<-eoruby
    10.times { Object.new }
    eoruby
    as = ObjectSpace::AllocationSampler.new(interval: 1, location: true)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>10}}}, as.result)
  end

  def test_location_mixed
    iseq = RubyVM::InstructionSequence.new <<-eoruby
    10.times { Object.new }
    Object.new
    eoruby
    as = ObjectSpace::AllocationSampler.new(interval: 1, location: true)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>10, 2=>1}}}, as.result)
  end

  def test_location_larger_interval
    iseq = RubyVM::InstructionSequence.new <<-eom
    100.times { Object.new }
    100.times { Object.new }
    eom
    as = ObjectSpace::AllocationSampler.new(interval: 10, location: true)
    as.enable
    iseq.eval
    as.disable

    assert_equal({"Object"=>{"<compiled>"=>{1=>10, 2=>10}}}, as.result)
    assert_equal 201, as.allocation_count
  end

  def test_interval_default
    as = ObjectSpace::AllocationSampler.new
    assert_equal 1, as.interval
  end

  def test_sanity
    as = ObjectSpace::AllocationSampler.new
    as.enable
    Object.new
    as.disable
    assert_equal({Object.name => 1}, as.result)
  end

  def test_two_with_same_type
    as = ObjectSpace::AllocationSampler.new
    as.enable
    Object.new
    Object.new
    as.disable

    assert_equal({Object.name => 2}, as.result)
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

    assert_equal(501, as.result[Object.name])
    assert_equal({Object.name=>501, TestAllocationSampler::X.name=>500}, as.result)
  end

  def test_interval
    as = ObjectSpace::AllocationSampler.new(interval: 10)
    as.enable
    500.times do
      Object.new
    end
    as.disable
    assert_equal({Object.name=>50}, as.result)
  end
end
