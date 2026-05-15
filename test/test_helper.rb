ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Force single-process tests. Rails' default parallelize(workers:
    # :number_of_processors) fork-spawns workers that each call pg's
    # PQconnectStart, which segfaults on arm64 macOS because libpq's
    # internal state isn't fork-safe. The suite is fast enough single-
    # threaded that the speedup isn't worth the platform-specific crash.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
