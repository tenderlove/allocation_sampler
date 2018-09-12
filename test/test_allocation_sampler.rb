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

  def test_two_with_same_type_same_line
    as = ObjectSpace::AllocationSampler.new
    as.enable
    Object.new; Object.new
    Object.new; Object.new
    as.disable

    assert_equal 4, as.result.allocations_by_type[Object.name]
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

    result = as.result
    assert_equal 501, result.allocations_by_type[Object.name]
    assert_equal 500, result.allocations_by_type[TestAllocationSampler::X.name]
  end

  def d
    Object.new
  end
  def c;  5.times { d }; end
  def b;  5.times { c }; end
  def a;  5.times { b }; end

  def test_stack_trace
    as = ObjectSpace::AllocationSampler.new
    buffer = StringIO.new
    stack_printer = ObjectSpace::AllocationSampler::Display::Stack.new(
      output: buffer
    )
    as.enable
    a
    as.disable

    as.result.by_type_with_call_tree.each do |class_name, tree|
      assert_equal Object.name, class_name
      root = tree.find { |node| node.name.include? __method__.to_s }
      stack_printer.show root
    end
    assert_equal <<-eoout, buffer.string
TestAllocationSampler#test_stack_trace  0   (0.0%)
`-- TestAllocationSampler#a             0   (0.0%)
    `-- TestAllocationSampler#b         0   (0.0%)
        `-- TestAllocationSampler#c     0   (0.0%)
            `-- TestAllocationSampler#d 125 (100.0%)
    eoout
  end

  def test_dot
    as = ObjectSpace::AllocationSampler.new
    as.enable
    a
    as.disable

    File.write 'out.dot', as.result.calltree.to_dot
  end

  private

  def filter result
    result.allocations_with_top_frame
  end
end
