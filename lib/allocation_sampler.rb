require 'allocation_sampler.so'
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

    def tree
      if location?
        Nodes::Root.new result.map { |type, files|
          Nodes::Type.new type, files.map { |path, lines|
            Nodes::Path.new path, lines.map { |line, count|
              Nodes::Line.new line, count
            }
          }
        }
      else
        Nodes::Root.new result.map { |type, count|
          Nodes::Type.new type, count
        }
      end
    end
  end
end
