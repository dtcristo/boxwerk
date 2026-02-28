# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :user
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }

  def total_cents
    product.price_cents * quantity
  end
end
