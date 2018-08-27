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

    assert_equal(4, filter(as.result)[Object.name].values.flat_map(&:values).inject(:+))
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

  def d
    Object.new
  end
  def c2; 5.times { d } end
  def c;  5.times { d }; end
  def b;  50.times { rand < 0.5 ? c : c2 }; end
  def a;  5.times { b }; end

  def max_width frame, incoming_edges, depth, seen
    return 0 if seen.key? frame[:id]
    seen[frame[:id]] = true

    my_length = (depth * 4) + frame[:name].length

    callers = (incoming_edges[frame[:id]] || [])

    callers.each do |caller|
      child_len = max_width caller, incoming_edges, depth + 1, seen
      my_length = child_len if my_length < child_len
    end

    my_length
  end

  def display frame, incoming_edges, depth, total_samples, last_stack, seen, max_width
    return if seen.key? frame[:id]
    seen[frame[:id]] = true

    buffer = max_width - ((depth * 4) + frame[:name].length)

    call, total = frame.values_at(:samples, :total_samples)
    last_stack.each_with_index do |last, i|
      if i == last_stack.length - 1
        if last
          printf "`-- "
        else
          printf "|-- "
        end
      else
        if last
          printf "    "
        else
          printf "|   "
        end
      end
    end


    printf frame[:name]
    #printf " " * buffer
    #printf "% d % 8s  % 10d % 8s", total, "(%2.1f%%)" % (total*100.0/total_samples), call, "(%2.1f%%)" % (call*100.0/total_samples)
    puts
    callers = (incoming_edges[frame[:id]] || []).sort_by { |frame|
      -frame[:total_samples]
    }

    callers.each_with_index do |caller, i|
      s = last_stack + [i == callers.length - 1]
      display caller, incoming_edges, depth + 1, total_samples, s, seen, max_width
    end
  end

  def test_stack_trace
    as = ObjectSpace::AllocationSampler.new
    as.enable
    a
    as.disable
    as.heaviest_types_by_file_and_line.each do |count, class_name, root, file, line, frames|
      incoming_edges = {}
      frames.each do |frame|
        if frame[:edges]
          frame[:edges].keys.each { |k| (incoming_edges[k] ||= []) << frame }
        end
      end

      puts
      puts "=================================="
      puts "#{class_name}: #{file}:#{line}"
      puts "=================================="
      max_width = max_width(root, incoming_edges, 0, {})
      display(root, incoming_edges, 0, root[:samples], [], {}, max_width)
    end
  end

  private

  def filter result
    result.each_with_object({}) do |(k, top_frames), a|
      file_table = a[k] ||= {}

      top_frames.each do |top_frame_info|
        top_frame = top_frame_info[:frames][top_frame_info[:root]]
        line_table = file_table[top_frame[:file]] ||= {}
        top_frame[:lines].each do |line, (_, count)|
          line_table[line] = count
        end
      end
    end
  end
end
