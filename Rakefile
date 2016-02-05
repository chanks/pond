require 'bundler/gem_tasks'

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new :default do |spec|
  spec.pattern = './spec/**/*_spec.rb'
end

Dir[File.dirname(__FILE__) + '/tasks/**/*.rake'].sort.each &method(:load)
