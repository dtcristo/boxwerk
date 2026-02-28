# frozen_string_literal: true

# Private: internal service for user validation logic.
class UserValidator
  def self.valid_email?(email)
    email.match?(/\A[^@\s]+@[^@\s]+\z/)
  end
end
