# -*- ruby -*-

require 'rubygems'
require 'hoe'
require 'rake/extensiontask'

Hoe.plugin :minitest
Hoe.plugin :gemspec # `gem install hoe-gemspec`
Hoe.plugin :git     # `gem install hoe-git`

HOE = Hoe.spec 'allocation_sampler' do
  developer('Aaron Patterson', 'aaron@tenderlovemaking.com')
  self.readme_file   = 'README.md'
  self.history_file  = 'CHANGELOG.md'
  self.extra_rdoc_files  = FileList['*.md']
  self.license 'MIT'
  self.spec_extras = {
    :extensions => ["ext/allocation_sampler/extconf.rb"],
  }
end

Rake::ExtensionTask.new("allocation_sampler", HOE.spec)

task :default => [:compile, :test]

# vim: syntax=ruby
