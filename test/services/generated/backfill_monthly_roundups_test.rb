require "test_helper"

module Generated
  class BackfillMonthlyRoundupsTest < ActiveSupport::TestCase
    setup do
      Civic::Jurisdiction.seed_defaults!
      @jurisdiction = Civic::Jurisdiction.default
      @as_of = Date.new(2026, 6, 15)
      @client = FakeClient.new
    end

    # Helper: seed a matter with passed_date in May 2026 so that month has
    # activity.
    def create_may_activity
      Civic::Matter.create!(
        legistar_matter_id: 80_001,
        matter_file: "26-900",
        passed_date: Date.new(2026, 5, 15),
        source_system: "legistar.sanjose"
      )
    end

    test "dry run finds candidates but does not call the model" do
      create_may_activity

      result = BackfillMonthlyRoundups.call(
        dry_run: true,
        client: @client,
        jurisdiction: @jurisdiction,
        as_of: @as_of
      )

      assert_includes result.candidates.map(&:label), "May 2026"
      assert_equal 0, result.generated
      assert_equal 0, @client.calls
    end

    test "non-dry run generates roundups" do
      create_may_activity

      result = BackfillMonthlyRoundups.call(
        dry_run: false,
        client: @client,
        jurisdiction: @jurisdiction,
        as_of: @as_of
      )

      assert_equal 1, result.generated
      assert_equal 1, @client.calls
      assert Generated::Artifact.exists?(
        target_type: "Civic::RoundupPeriod",
        kind: "monthly_roundup",
        status: "succeeded"
      )
    end

    test "freeze: already-generated period is not re-candidate" do
      create_may_activity

      # First run generates May 2026.
      BackfillMonthlyRoundups.call(
        dry_run: false,
        client: @client,
        jurisdiction: @jurisdiction,
        as_of: @as_of
      )

      # Second run should find no candidates (May is frozen).
      second = BackfillMonthlyRoundups.call(
        dry_run: false,
        client: @client,
        jurisdiction: @jurisdiction,
        as_of: @as_of
      )

      assert_equal 0, second.candidates.size
      assert_equal 0, second.generated
      assert_equal 1, @client.calls
    end

    test "force: true regenerates a frozen period" do
      create_may_activity

      # First run generates May 2026.
      BackfillMonthlyRoundups.call(
        dry_run: false,
        client: @client,
        jurisdiction: @jurisdiction,
        as_of: @as_of
      )

      # Force re-runs even though May is frozen.
      result = BackfillMonthlyRoundups.call(
        dry_run: false,
        client: @client,
        jurisdiction: @jurisdiction,
        force: true,
        as_of: @as_of
      )

      assert_equal 1, result.candidates.size
      assert_equal 2, @client.calls
    end

    test "activity gate: no activity means no candidates" do
      result = BackfillMonthlyRoundups.call(
        dry_run: true,
        client: @client,
        jurisdiction: @jurisdiction,
        as_of: @as_of
      )

      assert_equal 0, result.candidates.size
    end

    test "explicit month targets a specific month" do
      create_may_activity

      result = BackfillMonthlyRoundups.call(
        dry_run: true,
        client: @client,
        jurisdiction: @jurisdiction,
        month: Date.new(2026, 5, 1),
        as_of: @as_of
      )

      assert_includes result.candidates.map(&:label), "May 2026"
    end

    private

    class FakeClient
      attr_reader :calls, :model_name, :max_input_chars

      def initialize
        @calls = 0
        @model_name = "test-roundup-model"
        @max_input_chars = 18_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        Generated::RoundupClient::Response.new(
          model_name:,
          content: {
            "headline" => "H",
            "intro" => "I",
            "storyline" => "S"
          },
          usage_metadata: { "total_tokens" => 1 }
        )
      end
    end
  end
end
