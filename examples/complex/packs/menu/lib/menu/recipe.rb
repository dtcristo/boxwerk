# frozen_string_literal: true

module Menu
  class Recipe
    attr_reader :item, :steps

    def initialize(item:, steps:)
      @item = item
      @steps = steps
    end

    def instruction
      steps.join(' → ')
    end
  end
end
