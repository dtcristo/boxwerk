# frozen_string_literal: true

module Orders
  @orders = []

  class << self
    attr_reader :orders
  end
end
