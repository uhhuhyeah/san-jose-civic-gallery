require "test_helper"

# Exercises how the public event page surfaces an AI meeting summary: the
# summary and its disclaimer render when a successful event_summary artifact
# exists, and nothing extra renders when one does not.
class EventSummaryDisplayTest < ActionDispatch::IntegrationTest
  SANJOSE_HOST = "sanjose.civicgallery.org".freeze

  setup do
    @event = Civic::Event.create!(
      legistar_event_id: 83_001,
      body_name: "City Council",
      title: "Regular Meeting",
      event_date: Date.new(2026, 5, 12),
      minutes_status_name: "Final"
    )
  end

  test "renders the summary and disclaimer when an artifact exists" do
    create_summary(
      summary: "The council took up an affordable housing agreement and a paving budget.",
      key_topics: [ "Affordable housing agreement" ],
      limitations: [ "Based on the published minutes." ]
    )

    host! SANJOSE_HOST
    get public_event_url(@event)

    assert_response :success
    assert_includes response.body, "Meeting Summary"
    assert_includes response.body, "affordable housing agreement"
    assert_includes response.body, "Affordable housing agreement"
    assert_includes response.body, "Based on the published minutes."
    assert_includes response.body, "does not report outcomes or votes"
  end

  test "does not render the summary section when no artifact exists" do
    host! SANJOSE_HOST
    get public_event_url(@event)

    assert_response :success
    assert_not_includes response.body, "Meeting Summary"
  end

  test "does not render a failed summary artifact" do
    Generated::Artifact.create!(
      target: @event,
      kind: Generated::SummarizeEvent::KIND,
      status: "failed",
      model_identifier: "test-event-model",
      prompt_version: Generated::SummarizeEvent::PROMPT::VERSION,
      input_sha256: "failed-sha",
      content: {},
      error_message: "boom"
    )

    host! SANJOSE_HOST
    get public_event_url(@event)

    assert_response :success
    assert_not_includes response.body, "Meeting Summary"
  end

  private

  def create_summary(summary:, key_topics:, limitations:)
    Generated::Artifact.create!(
      target: @event,
      kind: Generated::SummarizeEvent::KIND,
      status: "succeeded",
      model_identifier: "test-event-model",
      prompt_version: Generated::SummarizeEvent::PROMPT::VERSION,
      input_sha256: "summary-sha",
      content: { "summary" => summary, "key_topics" => key_topics, "limitations" => limitations }
    )
  end
end
