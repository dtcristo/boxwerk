# frozen_string_literal: true

module Menu
  @items = []

  class << self
    attr_reader :items
  end
end
