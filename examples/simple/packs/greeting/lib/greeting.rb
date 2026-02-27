# frozen_string_literal: true

require 'faker'

class Greeting
  def self.hello
    Faker::Name.name
  end

  def self.faker_version
    Faker::VERSION
  end
end
