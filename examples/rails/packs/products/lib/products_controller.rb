# frozen_string_literal: true

class ProductsController < ApplicationController
  def index
    render json: Product.all
  end

  def show
    render json: Product.find(params[:id])
  end

  def create
    product = Product.create!(product_params)
    render json: product, status: :created
  end

  private

  def product_params
    params.permit(:name, :price_cents)
  end
end
