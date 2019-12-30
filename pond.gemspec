# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pond/version'

Gem::Specification.new do |spec|
  spec.name          = 'pond'
  spec.version       = Pond::VERSION
  spec.authors       = ["Chris Hanks"]
  spec.email         = ["christopher.m.hanks@gmail.com"]
  spec.description   = %q{A simple, generic, thread-safe pool for connections or whatever else}
  spec.summary       = %q{A simple, generic, thread-safe pool}
  spec.homepage      = 'https://github.com/chanks/pond'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '>= 1.3'
  spec.add_development_dependency 'rspec',   '>= 2.14'
  spec.add_development_dependency 'rake'
end
