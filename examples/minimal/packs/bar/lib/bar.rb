# frozen_string_literal: true

class Bar
  def self.call
    'bar'
  end

  def self.baz_call
    Baz.call
  end
end
