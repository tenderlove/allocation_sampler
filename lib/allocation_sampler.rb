require 'allocation_sampler.so'
require 'delegate'

module ObjectSpace
  class AllocationSampler
    VERSION = '1.0.0'

    class Result
      class Frame
        attr_reader :id, :name, :count, :callers

        def initialize id, name, path, line, count, callers
          @id = id
          @name   = name
          @path     = path
          @line     = line
          @count    = count
          @callers = callers
        end

        def total_samples
          0
        end
      end

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
          _, path = @frames[top_frame_id]
          ((h[type] ||= {})[path] ||= {})[line] = count
        end
      end

      def allocations_with_call_tree
        types_with_stacks = @samples.group_by(&:first)
        types_with_stacks.map do |type, stacks|
          seed = build_initial_tree(*stacks.shift)
          #_tree = stacks.inject(seed) do |tree, (_, count, stack)|
          #end
          [type, seed]
        end
      end

      private

      def build_initial_tree type, count, stack
        bottom_up = stack.reverse
        _frame_id, _line = bottom_up.shift
        initial = build_frame _frame_id, _line, count, nil

        bottom_up.inject(initial) do |node, (frame_id, line)|
          build_frame frame_id, line, count, [node]
        end
      end

      def build_frame frame_id, line, count, child
        method, path = @frames[frame_id]
        Frame.new frame_id, method, path, line, count, child
      end
    end

    def result
      Result.new samples, frames
    end

    module Display
      class Stack < DelegateClass(IO)
        attr_reader :max_depth

        def initialize output: $stdout, max_depth: 0
          @max_depth = max_depth
          super(output)
        end

        def show frames
          max_width = max_width(frames, 0, {})
          display(frames, 0, frames.count, [], {}, max_width)
        end

        private

        def too_deep? depth
          max_depth != 0 && depth > max_depth - 1
        end

        def max_width frame, depth, seen
          if too_deep? depth
            return 0
          end

          if seen.key? frame
            return 0
          end

          seen[frame] = true

          my_length = (depth * 4) + frame.name.length

          frame.callers.each do |caller|
            child_len = max_width caller, depth + 1, seen
            my_length = child_len if my_length < child_len
          end

          my_length
        end

        def display frame, depth, total_samples, last_stack, seen, max_width
          return if too_deep? depth
          if seen.key? frame
            return
          else
            seen[frame] = true
          end


          buffer = max_width - ((depth * 4) + frame.name.length)

          call = frame.count
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
          printf "% d % 8s", call, "(%2.1f%%)" % (call*100.0/total_samples)
          puts
          callers = (frame.callers || []).sort_by { |ie|
            -ie.total_samples
          }.reject { |caller| seen[caller.id] }

          callers.each_with_index do |caller, i|
            s = last_stack + [i == callers.length - 1]
            display caller, depth + 1, total_samples, s, seen, max_width
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
      result.allocations_with_call_tree
    end
  end
end
