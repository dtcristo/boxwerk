# frozen_string_literal: true

module Loyalty
  @cards = []

  class << self
    attr_reader :cards
  end
end
