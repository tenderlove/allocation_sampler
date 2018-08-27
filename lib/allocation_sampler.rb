require 'allocation_sampler.so'
require 'delegate'

module ObjectSpace
  class AllocationSampler
    VERSION = '1.0.0'

    module Nodes
      class Node
        attr_reader :children

        def initialize children
          @children = children
          @count    = nil
        end

        def to_i
          @count ||= children.map(&:to_i).inject :+
        end

        def pct of
          to_i / of.to_i.to_f
        end
      end
      class Root < Node; end

      class Type < Node
        attr_reader :name

        def initialize name, children
          @name = name
          super(children)
        end
      end

      class Path < Type; end
      class Line < Struct.new(:number, :to_i)
        def pct of
          to_i / of.to_i.to_f
        end
      end
    end

    module Aggregators
      def self.location root, io = $stdout
        Location.new.display root, io
      end

      class Location
        def display root, io, min = 0.05
          root.children.sort_by(&:to_i).reverse_each do |type|
            next if pct(type, root) < min

            puts "#{type.name} #{pct_s(type, root)}"
            type.children.sort_by(&:to_i).reverse_each do |path|
              next if pct(path, type) < min
              puts "  #{path.name} #{pct_s(path, root)} #{pct_s(path, type)}"

              path.children.sort_by(&:to_i).reverse_each do |line|
                next if pct(line, path) < min && path.children.length > 1
                puts "    #{line.number} #{pct_s(line, root)}"
              end
            end
          end
        end

        def pct a, b
          a.to_i / b.to_i.to_f
        end

        def pct_s a, b
          "#{a.to_i} / #{b.to_i} (" + sprintf("%.2f", pct(a, b) * 100) + ")%"
        end
      end
    end

    module Display
      class Stack < DelegateClass(IO)
        attr_reader :max_depth

        def initialize output: $stdout, max_depth: 0
          @max_depth = max_depth
          super(output)
        end

        def show frames
          max_width = max_width(frames.root, frames.incoming_edges, 0, {})
          display(frames.root, frames.incoming_edges, 0, frames.root[:samples], [], {}, max_width)
        end

        private

        def too_deep? depth
          max_depth != 0 && depth > max_depth - 1
        end

        def max_width frame, incoming_edges, depth, seen
          return 0 if too_deep? depth
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
          return if too_deep? depth
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
          printf " " * buffer
          printf "% d % 8s  % 10d % 8s", total, "(%2.1f%%)" % (total*100.0/total_samples), call, "(%2.1f%%)" % (call*100.0/total_samples)
          puts
          callers = (incoming_edges[frame[:id]] || []).sort_by { |ie|
            -ie[:total_samples]
          }.reject { |caller| seen[caller[:id]] }

          callers.each_with_index do |caller, i|
            s = last_stack + [i == callers.length - 1]
            display caller, incoming_edges, depth + 1, total_samples, s, seen, max_width
          end
        end
      end
    end

    class FramesCollection < DelegateClass(Array)
      attr_reader :root

      def initialize root, array
        super(array)
        @root = root
        @incoming_edges = nil
      end

      def incoming_edges
        @incoming_edges ||= each_with_object({}) do |frame, incoming_edges|
          if frame[:edges]
            frame[:edges].keys.each { |k| (incoming_edges[k] ||= []) << frame }
          end
        end
      end
    end

    def heaviest_types_by_file_and_line
      result = self.result
      thing = result.flat_map do |class_name, top_frames|
        top_frames.flat_map do |info|
          frames = info[:frames]
          frame_id = info[:root]
          root = frames[frame_id]
          collection = FramesCollection.new root, frames.values
          root[:lines].map do |line, (_, count)|
            [count, class_name, root[:file], line, collection]
          end
        end
      end
      thing.sort_by!(&:first).reverse!
    end
  end
end
