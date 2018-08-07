require 'minitest/autorun'
require 'allocation_sampler'

class TestAllocationSampler < Minitest::Test
  def test_initialize
    assert ObjectSpace::AllocationSampler.new
  end

  def test_sanity
    as = ObjectSpace::AllocationSampler.new
    as.enable
    Object.new
    as.disable
    assert_equal({Object => 1}, as.result)
  end

  def test_two_with_same_type
    as = ObjectSpace::AllocationSampler.new
    as.enable
    Object.new
    Object.new
    as.disable

    assert_equal({Object => 2}, as.result)

    # Make sure we're aggregating types
    assert_equal(1, as.record_count)
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

    assert_equal(501, as.result[Object])
    assert_equal({Object=>501, TestAllocationSampler::X=>500}, as.result)
  end
end
