# frozen_string_literal: true

class LineItem
  attr_reader :description, :amount_cents

  def initialize(description, amount_cents)
    @description = description
    @amount_cents = amount_cents
  end

  def to_s
    "#{description}: #{amount_cents}"
  end
end
