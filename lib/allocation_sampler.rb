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
          @children = []
        end

        def each
          seen = {}
          stack = [self]

          while node = stack.pop
            next if seen[node]
            seen[node] = true
            yield node
            stack.concat node.children
          end
        end

        def to_dot
          seen = {}
          "digraph allocations {\n" +
            "  node[shape=record];\n" + print_edges(self, seen, total_samples) + "}\n"
        end

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
        root  = Set.new

        frame_delegates = {}
        @samples.each do |type, count, stack|
          root << build_tree(stack, count, frame_delegates)
        end
        # We should only ever have one root
        root.first
      end

      def allocations_with_call_tree
        types_with_stacks = @samples.group_by(&:first)
        types_with_stacks.map do |type, stacks|
          frame_delegates = {}
          root = Set.new
          stacks.each do |_, count, stack|
            root << build_tree(stack, count, frame_delegates)
          end
          [type, root.first]
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

        def initialize output: $stdout, max_depth: 0
          @max_depth = max_depth
          super(output)
        end

        def show frames
          max_width = max_width(frames, 0, {})
          display(frames, 0, frames.total_samples, [], {}, max_width)
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

          frame.children.each do |caller|
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
          callers = (frame.children || []).sort_by { |ie|
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
