# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false
      t.references :product, null: false
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
  end
end
