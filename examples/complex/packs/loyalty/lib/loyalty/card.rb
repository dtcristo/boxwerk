# frozen_string_literal: true

module Loyalty
  class Card
    attr_reader :member_name, :points

    def initialize(member_name: nil)
      @member_name = member_name || Faker::Name.name
      @points = 0
      Loyalty.cards << self
    end

    def earn(amount_cents)
      @points += amount_cents / 100
    end

    def to_s
      "#{member_name}: #{points} pts"
    end

    def self.faker_version
      Faker::VERSION
    end
  end
end
