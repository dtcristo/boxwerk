# frozen_string_literal: true

class OrdersController < ApplicationController
  def index
    render json: Order.includes(:user, :product).all
  end

  def show
    render json: Order.includes(:user, :product).find(params[:id])
  end

  def create
    order = Order.create!(order_params)
    render json: order, status: :created
  end

  private

  def order_params
    params.permit(:user_id, :product_id, :quantity)
  end
end
