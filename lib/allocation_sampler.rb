require 'allocation_sampler.so'
module ObjectSpace
  class AllocationSampler
    VERSION = '1.0.0'

    def display io = $stdout
      if location?
        display_with_location result, io
      else
        display_without_location result, io
      end
    end

    private

    def display_with_location info, io
      sum_allocations = Hash.new 0
      info.each_pair { |class_name, locations|
        sum_allocations[class_name] = locations.values.flat_map(&:values).inject(:+)
      }
      sample_count = sum_allocations.values.inject :+

      records = info.sort_by { |name, _| sum_allocations[name] }.reverse
      records.each do |name, paths|
        io.puts "#{name} (#{pct(sum_allocations[name], sample_count)}):"
        paths = paths.sort_by { |_, lines| lines.values.inject(:+) }.reverse
        paths.each do |path, lines|
          lines.sort_by { |_, count| count }.reverse.each do |line, count|
            puts "  #{path}:#{line}: #{pct(count, sample_count)} #{pct(count, sum_allocations[name])}"
          end
        end
      end
    end

    def pct a, b
      "#{a} / #{b} (" + sprintf("%.2f", (a / b.to_f) * 100) + ")%"
    end

    def display_without_location info
      raise
    end
  end
end
