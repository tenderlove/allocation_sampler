require 'allocation_sampler/version'
require 'allocation_sampler.so'
require 'delegate'
require 'set'
require 'cgi/escape'

module ObjectSpace
  class AllocationSampler
    VERSION = '1.0.0'

    class Frame
      attr_reader :id, :name, :path, :children

      def initialize id, name, path
        @id       = id
        @name     = name
        @path     = path
      end
    end

    class Result
      class Frame < DelegateClass(AllocationSampler::Frame)
        attr_reader :line, :children
        attr_accessor :samples, :total_samples

        include Enumerable

        def initialize frame, line, samples
          super(frame)
          @line = line
          @samples = samples
          @total_samples = 0
          @children = Set.new
        end

        def each
          seen = {}
          stack = [self]

          while node = stack.pop
            next if seen[node]
            seen[node] = true
            yield node
            stack.concat node.children.to_a
          end
        end

        def to_dot
          seen = {}
          "digraph allocations {\n" +
            "  node[shape=record];\n" + print_edges(self, seen, total_samples) + "}\n"
        end

        private

        def print_edges node, seen, total_samples
          return '' if seen[node.id]
          seen[node.id] = node
          "  #{node.id} [label=\"#{CGI.escapeHTML node.name}\"];\n" +
            node.children.map { |child|
            ratio = child.total_samples / total_samples.to_f
            width = (1 * ratio) + 1
            "  #{node.id} -> #{child.id} [penwidth=#{width}];\n" + print_edges(child, seen, total_samples)
          }.join
        end
      end

      attr_reader :samples, :frames

      def initialize samples, frames
        @samples = samples.sort_by! { |s| s[1] }.reverse!
        @frames = frames
      end

      def allocations_by_type
        @samples.each_with_object(Hash.new(0)) do |(type, count, _), h|
          h[type] += count
        end
      end

      def allocations_with_top_frame
        @samples.each_with_object({}) do |(type, count, stack), h|
          top_frame_id, line = stack.first
          frame = @frames[top_frame_id]
          ((h[type] ||= {})[frame.path] ||= {})[line] = count
        end
      end

      def calltree
        frame_delegates = {}
        @samples.map { |type, count, stack|
          build_tree(stack, count, frame_delegates)
        }.uniq.first
      end

      def by_type_with_call_tree
        types_with_stacks = @samples.group_by(&:first)
        types_with_stacks.transform_values do |stacks|
          frame_delegates = {}
          stacks.map { |_, count, stack|
            build_tree(stack, count, frame_delegates)
          }.uniq.first
        end
      end

      private

      def build_tree stack, count, frame_delegates
        top_down = stack.reverse
        last_caller = nil
        seen = Set.new
        root = nil
        top_frame_id, top_line = stack.first
        top = frame_delegates[top_frame_id] ||= build_frame(top_frame_id, top_line, 0)
        top.samples += count
        top_down.each do |frame_id, line|
          frame = frame_delegates[frame_id] ||= build_frame(frame_id, line, 0)
          root ||= frame
          if last_caller
            last_caller.children << frame
          end
          last_caller = frame
          last_caller.total_samples += count unless seen.include?(frame_id)
          seen << frame_id
        end
        root
      end

      def build_frame id, line, samples
        Frame.new @frames[id], line, samples
      end
    end

    def result
      Result.new samples, frames
    end

    module Display
      class Stack < DelegateClass(IO)
        attr_reader :max_depth

        def initialize output: $stdout
          super(output)
        end

        def show frames
          max_width = max_width(frames, 0, {})
          display(frames, 0, frames.total_samples, [], {}, max_width)
        end

        private

        def max_width frame, depth, seen
          if seen.key? frame
            return 0
          end

          seen[frame] = true

          my_length = (depth * 4) + frame.name.length

          frame.children.each do |caller|
            child_len = max_width caller, depth + 1, seen
            my_length = child_len if my_length < child_len
          end

          my_length
        end

        def display frame, depth, total_samples, last_stack, seen, max_width
          seen[frame] = true


          buffer = max_width - ((depth * 4) + frame.name.length)

          self_samples = frame.samples
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


          printf frame.name
          printf " " * buffer
          printf "% d % 8s", self_samples, "(%2.1f%%)" % (self_samples*100.0/total_samples)
          puts

          children = (frame.children || []).sort_by { |ie|
            -ie.total_samples
          }.reject { |f| seen[f] }

          children.each_with_index do |child, i|
            s = last_stack + [i == children.length - 1]
            display child, depth + 1, total_samples, s, seen, max_width
          end
        end
      end
    end
  end
end
