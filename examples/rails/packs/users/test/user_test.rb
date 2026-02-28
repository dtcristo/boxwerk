# frozen_string_literal: true

require_relative '../../../test/test_helper'

class UserTest < RailsTestCase
  def test_create_user
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    assert_equal 'Alice', user.name
    assert_equal 'alice@example.com', user.email
  end

  def test_name_required
    user = User.new(email: 'alice@example.com')
    refute user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  def test_email_required
    user = User.new(name: 'Alice')
    refute user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  def test_user_validator_accessible_internally
    assert UserValidator.valid_email?('alice@example.com')
    refute UserValidator.valid_email?('bad')
  end
end
