# frozen_string_literal: true

require 'pond'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = [:expect, :should] }
end
