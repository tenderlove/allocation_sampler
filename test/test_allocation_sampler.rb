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
    #assert_equal(1, as.record_count)
  end
end
