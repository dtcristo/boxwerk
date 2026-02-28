# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'

# Connect to a separate test database
db_path = File.join(__dir__, '..', 'db', 'test.sqlite3')
FileUtils.rm_f(db_path)
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: db_path)

# Run migrations
ActiveRecord::MigrationContext.new(
  File.join(__dir__, '..', 'db', 'migrate'),
).migrate

# Base test class that wraps each test in a rolled-back transaction
class RailsTestCase < Minitest::Test
  def setup
    @_test_txn =
      ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end
end
