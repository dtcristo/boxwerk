# frozen_string_literal: true

module Kitchen
  class Barista
    attr_reader :name

    def initialize(name: nil)
      @name = name || Faker::Name.first_name
    end

    def prepare(menu_item)
      ticket = menu_item.name.to_order_ticket
      "#{@name} is preparing #{ticket} (#{PrepService.queue_count} in queue)"
    end

    def self.faker_version
      Faker::VERSION
    end
  end
end
