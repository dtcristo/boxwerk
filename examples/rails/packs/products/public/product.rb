# frozen_string_literal: true

class Product < ApplicationRecord
  validates :name, presence: true
  validates :price_cents, numericality: { greater_than: 0 }

  def price
    format('$%.2f', price_cents / 100.0)
  end
end
