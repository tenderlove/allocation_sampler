# frozen_string_literal: true

require_relative "lib/allocation_sampler/version"

Gem::Specification.new do |s|
  s.name = %q{allocation_sampler}
  s.version = ObjectSpace::AllocationSampler::VERSION
  s.authors = ['Aaron Patterson']
  s.email = ['aaron@tenderlovemaking.com']
  s.summary = 'A sampling allocation profiler.'
  s.description = "This keeps track of allocations, but only onspecified intervals. Useful for profiling allocations in programs where there is a time limit on completion of the program."
  s.extensions = %w(ext/allocation_sampler/extconf.rb)
  s.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    %x(git ls-files -z).split("\x0").reject { |f| f.match(%r{^(test|spec|features|bin|\.)/}) }
  end

  s.homepage = 'https://github.com/tenderlove/allocation_sampler'
  s.licenses = ['MIT']
end
