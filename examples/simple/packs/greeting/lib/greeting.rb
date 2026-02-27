# frozen_string_literal: true

require 'faker'

class Greeting
  def self.hello
    name = Faker::Name.name
    prefix = ENV['GREETING_PREFIX']
    prefix ? "#{prefix}, #{name}" : name
  end

  def self.faker_version
    Faker::VERSION
  end
end
