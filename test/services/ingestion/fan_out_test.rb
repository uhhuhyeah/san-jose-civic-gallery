require "test_helper"

module Ingestion
  class FanOutTest < ActiveSupport::TestCase
    test "calls the inline lambda for :inline mode" do
      called = []
      FanOut.dispatch(
        mode: :inline,
        inline: -> { called << :inline },
        deferred: -> { called << :deferred }
      )
      assert_equal [ :inline ], called
    end

    test "calls the deferred lambda for :deferred mode" do
      called = []
      FanOut.dispatch(
        mode: :deferred,
        inline: -> { called << :inline },
        deferred: -> { called << :deferred }
      )
      assert_equal [ :deferred ], called
    end

    test "calls nothing for :off" do
      called = []
      result = FanOut.dispatch(
        mode: :off,
        inline: -> { called << :inline },
        deferred: -> { called << :deferred }
      )
      assert_equal [], called
      assert_nil result
    end

    test "true normalizes to inline, false normalizes to off" do
      called = []
      FanOut.dispatch(mode: true, inline: -> { called << :inline })
      assert_equal [ :inline ], called

      FanOut.dispatch(mode: false, inline: -> { called << :inline })
      assert_equal [ :inline ], called  # not appended again
    end

    test "missing lambda for the matching mode is a no-op rather than raising" do
      assert_nothing_raised do
        FanOut.dispatch(mode: :inline, deferred: -> { raise "should not run" })
      end
    end
  end
end
