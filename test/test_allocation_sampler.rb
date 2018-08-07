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
