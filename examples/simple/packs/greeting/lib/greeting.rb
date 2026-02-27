# frozen_string_literal: true

class Greeting
  def self.hello
    require 'faker'
    Faker::Name.name
  end

  def self.faker_version
    require 'faker'
    Faker::VERSION
  end
end
