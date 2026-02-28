# frozen_string_literal: true

require 'faker'

module Kitchen
  class Barista
    attr_reader :name

    def initialize(name: nil)
      @name = name || Faker::Name.first_name
    end

    def prepare(menu_item)
      "#{@name} is preparing #{menu_item.name} (#{PrepService.queue_count} in queue)"
    end

    def self.faker_version
      Faker::VERSION
    end
  end
end
