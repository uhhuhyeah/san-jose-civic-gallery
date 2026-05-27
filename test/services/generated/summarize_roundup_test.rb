require "test_helper"

module Generated
  class SummarizeRoundupTest < ActiveSupport::TestCase
    setup do
      Civic::Jurisdiction.seed_defaults!
      @jurisdiction = Civic::Jurisdiction.default
      @period = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)
      @client = FakeRoundupClient.new

      # Seed one in-window decision so the month has content.
      @matter = Civic::Matter.create!(
        legistar_matter_id: 70_001,
        matter_file: "26-700",
        title: "Affordable housing agreement",
        passed_date: Date.new(2026, 5, 15),
        source_system: "legistar.sanjose"
      )
    end

    test "generates a monthly_roundup artifact" do
      result = SummarizeRoundup.call(period: @period, client: @client)

      assert_equal false, result.skipped
      assert_equal "succeeded", result.artifact.status
      assert_equal "monthly_roundup", result.artifact.kind
      assert_equal @period, result.artifact.target
      assert_equal "test-roundup-model", result.artifact.model_identifier
      assert_equal Generated::Prompts::MonthlyRoundupV1::VERSION, result.artifact.prompt_version
      assert_equal "May in San Jose", result.artifact.content["headline"]
      assert_equal({ "total_tokens" => 42 }, result.artifact.usage_metadata)
    end

    test "idempotent for the same month data" do
      first = SummarizeRoundup.call(period: @period, client: @client)
      second = SummarizeRoundup.call(period: @period, client: @client)

      assert_equal first.artifact, second.artifact
      assert_equal true, second.skipped
      assert_equal 1, @client.calls
      assert_equal 1, Generated::Artifact.where(kind: "monthly_roundup").count
    end

    test "a changed month produces a new artifact" do
      first = SummarizeRoundup.call(period: @period, client: @client)

      # Add a second in-window decision so the input hash changes.
      Civic::Matter.create!(
        legistar_matter_id: 70_002,
        matter_file: "26-701",
        title: "Transportation funding resolution",
        passed_date: Date.new(2026, 5, 20),
        source_system: "legistar.sanjose"
      )

      # Fresh activity picks up the new matter.
      activity = Public::MonthlyActivity.new(
        jurisdiction: @period.civic_jurisdiction,
        period_start: @period.period_start,
        period_end: @period.period_end
      )

      second = SummarizeRoundup.call(period: @period, activity: activity, client: @client)

      assert_not_equal first.artifact.input_sha256, second.artifact.input_sha256
      assert_equal 2, Generated::Artifact.where(kind: "monthly_roundup").count
      assert_equal 2, @client.calls
    end

    test "client errors are captured on a failed artifact" do
      failing = FakeRoundupClient.new(error: RuntimeError.new("boom"))

      result = SummarizeRoundup.call(period: @period, client: failing)

      assert_equal "failed", result.artifact.status
      assert_equal "boom", result.artifact.error_message
    end

    test "a failing forced run does not downgrade an existing succeeded artifact" do
      SummarizeRoundup.call(period: @period, client: @client)
      assert_equal "succeeded", Generated::Artifact.find_by!(target: @period, kind: "monthly_roundup").status

      failing = FakeRoundupClient.new(error: RuntimeError.new("boom"))
      result = SummarizeRoundup.call(period: @period, client: failing, force: true)

      assert result.skipped
      assert_equal "raced", result.reason
      assert_equal "succeeded", Generated::Artifact.find_by!(target: @period, kind: "monthly_roundup").status
    end

    class FakeRoundupClient
      attr_reader :calls, :model_name, :max_input_chars, :last_user_prompt, :last_system_prompt

      def initialize(content: nil, error: nil)
        @content = content || default_content
        @error = error
        @calls = 0
        @model_name = "test-roundup-model"
        @max_input_chars = 18_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        @last_system_prompt = system_prompt
        @last_user_prompt = user_prompt
        raise @error if @error

        Generated::RoundupClient::Response.new(
          content: @content,
          model_name:,
          usage_metadata: { "total_tokens" => 42 }
        )
      end

      private

      def default_content
        {
          "headline" => "May in San Jose",
          "intro" => "Intro.",
          "storyline" => "Story."
        }
      end
    end
  end
end
