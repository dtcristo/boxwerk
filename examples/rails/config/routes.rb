# frozen_string_literal: true

Example::Application.routes.draw do
  resources :users, only: %i[index show create]
  resources :products, only: %i[index show create]
  resources :orders, only: %i[index show create]
end
