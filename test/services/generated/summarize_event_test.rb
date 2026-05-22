require "test_helper"

module Generated
  class SummarizeEventTest < ActiveSupport::TestCase
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 81_001,
        body_name: "City Council",
        title: "Regular Meeting",
        event_date: Date.new(2026, 5, 12),
        minutes_status_name: "Final"
      )
      @matter = Civic::Matter.create!(legistar_matter_id: 70_001, matter_file: "26-700", title: "Affordable housing agreement")
      @item = add_item(
        agenda_number: "3.1",
        title: "Affordable housing agreement",
        minutes_note: "Council heard public comment on the housing agreement and voted on the motion, carried 9-2.",
        matter: @matter,
        seq: 1
      )
      @client = FakeEventSummaryClient.new
    end

    test "summarizes an event into a generated artifact" do
      result = SummarizeEvent.call(event: @event, client: @client)

      assert_equal false, result.skipped
      assert_equal "succeeded", result.artifact.status
      assert_equal "event_summary", result.artifact.kind
      assert_equal @event, result.artifact.target
      assert_equal "test-event-model", result.artifact.model_identifier
      assert_equal "event_summary_v2", result.artifact.prompt_version
      assert_equal "The council took up housing and transportation items.", result.artifact.content["summary"]
      assert_equal 1, result.artifact.input_metadata["item_count"]
      assert_equal({ "total_tokens" => 55 }, result.artifact.usage_metadata)
    end

    test "sends the item record and theme hint to the model" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      SummarizeEvent.call(event: @event, client: @client)

      assert_includes @client.last_user_prompt, "Affordable housing agreement"
      assert_includes @client.last_user_prompt, "carried 9-2" # raw record is sent; the prompt forbids restating it
      assert_includes @client.last_user_prompt, "3.1: Housing"
    end

    test "prefers minutes note over agenda note for an item" do
      item = add_item(agenda_number: "4.2", title: "Budget item", minutes_note: "Minutes discussion text.", agenda_note: "Agenda description text.", seq: 2)

      SummarizeEvent.call(event: @event, client: @client)

      assert_includes @client.last_user_prompt, "Minutes discussion text."
      assert_not_includes @client.last_user_prompt, "Agenda description text."
    end

    test "is idempotent for the same item set, prompt, and model" do
      first = SummarizeEvent.call(event: @event, client: @client)
      second = SummarizeEvent.call(event: @event, client: @client)

      assert_equal first.artifact, second.artifact
      assert_equal true, second.skipped
      assert_equal 1, @client.calls
      assert_equal 1, Artifact.where(kind: "event_summary").count
    end

    test "a changed item set produces a new artifact" do
      first = SummarizeEvent.call(event: @event, client: @client)

      add_item(agenda_number: "5.1", title: "New rezoning hearing", minutes_note: "Heard the rezoning proposal.", seq: 3)
      second = SummarizeEvent.call(event: @event, client: @client)

      assert_not_equal first.artifact.input_sha256, second.artifact.input_sha256
      assert_equal 2, Artifact.where(kind: "event_summary").count
    end

    test "reclassifying a linked matter's themes does not change the input hash" do
      before = SummarizeEvent.current_input_sha256(event: @event, client: @client)

      @matter.themes.create!(theme_slug: "housing", rank: 1)
      @matter.themes.create!(theme_slug: "transportation", rank: 2)
      after = SummarizeEvent.current_input_sha256(event: @event.reload, client: @client)

      assert_equal before, after
    end

    test "records a missing-source skip when no item text exists" do
      empty_event = Civic::Event.create!(
        legistar_event_id: 81_999,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 13),
        minutes_status_name: "Final"
      )

      result = SummarizeEvent.call(event: empty_event, client: @client)

      assert_equal "failed", result.artifact.status
      assert_equal "missing_source_text", result.reason
      assert_equal 0, @client.calls
    end

    test "client errors are captured on a failed artifact" do
      failing = FakeEventSummaryClient.new(error: RuntimeError.new("budget exceeded"))

      result = SummarizeEvent.call(event: @event, client: failing)

      assert_equal "failed", result.artifact.status
      assert_equal "budget exceeded", result.artifact.error_message
    end

    test "a failing forced run does not downgrade an existing succeeded artifact" do
      SummarizeEvent.call(event: @event, client: @client)
      assert_equal "succeeded", Artifact.find_by!(target: @event, kind: "event_summary").status

      failing = FakeEventSummaryClient.new(error: RuntimeError.new("boom"))
      result = SummarizeEvent.call(event: @event, client: failing, force: true)

      assert result.skipped
      assert_equal "raced", result.reason
      assert_equal "succeeded", Artifact.find_by!(target: @event, kind: "event_summary").status
    end

    private

    def add_item(agenda_number:, title:, seq:, minutes_note: nil, agenda_note: nil, matter: nil)
      @item_seq ||= 0
      @item_seq += 1
      @event.all_event_items.create!(
        legistar_event_item_id: 90_000 + @item_seq,
        agenda_number:,
        title:,
        minutes_note:,
        agenda_note:,
        agenda_sequence: seq,
        matter:
      )
    end

    class FakeEventSummaryClient
      attr_reader :calls, :model_name, :max_input_chars, :last_user_prompt, :last_system_prompt

      def initialize(content: nil, error: nil)
        @content = content || default_content
        @error = error
        @calls = 0
        @model_name = "test-event-model"
        @max_input_chars = 18_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        @last_system_prompt = system_prompt
        @last_user_prompt = user_prompt
        raise @error if @error

        EventSummaryClient::Response.new(
          model_name:,
          content: @content,
          usage_metadata: { "total_tokens" => 55 }
        )
      end

      private

      def default_content
        {
          "summary" => "The council took up housing and transportation items.",
          "key_topics" => [ "Affordable housing agreement" ],
          "limitations" => []
        }
      end
    end
  end
end
