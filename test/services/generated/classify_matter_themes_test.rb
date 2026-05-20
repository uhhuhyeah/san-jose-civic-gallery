require "test_helper"

module Generated
  class ClassifyMatterThemesTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 50_001,
        matter_file: "26-300",
        title: "Affordable housing development agreement"
      )
      @attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 60_001,
        name: "Staff report"
      )
      @client = FakeThemesClient.new(themes: [ "housing", "land_use_zoning" ])
    end

    test "classifies a matter and projects themes into civic_matter_themes" do
      add_summary(summary: "Approves a 200-unit affordable housing project.", key_points: [ "Rezones the parcel." ])

      result = ClassifyMatterThemes.call(matter: @matter, client: @client)

      assert_equal false, result.skipped
      assert_equal "succeeded", result.artifact.status
      assert_equal "matter_themes", result.artifact.kind
      assert_equal @matter, result.artifact.target
      assert_equal [ "housing", "land_use_zoning" ], result.artifact.content["themes"]
      assert_equal %w[housing land_use_zoning].sort, @matter.themes.pluck(:theme_slug).sort
      assert_equal result.artifact.id, @matter.themes.first.source_artifact_id
    end

    test "stores theme rank in returned order, most central first" do
      add_summary(summary: "Affordable housing rezoning.", key_points: [])

      ClassifyMatterThemes.call(matter: @matter, client: @client)

      ranked = @matter.themes.by_rank.pluck(:theme_slug, :rank)
      assert_equal [ [ "housing", 1 ], [ "land_use_zoning", 2 ] ], ranked
    end

    test "re-classification rewrites ranks to the new order" do
      add_summary(summary: "Housing project.", key_points: [])
      ClassifyMatterThemes.call(matter: @matter, client: @client)

      reordered = FakeThemesClient.new(themes: [ "land_use_zoning", "housing" ])
      ClassifyMatterThemes.call(matter: @matter, client: reordered, force: true)

      assert_equal "land_use_zoning", @matter.themes.primary.first.theme_slug
      assert_equal [ [ "land_use_zoning", 1 ], [ "housing", 2 ] ], @matter.themes.by_rank.pluck(:theme_slug, :rank)
    end

    test "uses attachment summaries as source text when present" do
      add_summary(summary: "Discusses a new bike lane network.", key_points: [])

      ClassifyMatterThemes.call(matter: @matter, client: @client)

      assert_includes @client.last_user_prompt, "Discusses a new bike lane network."
    end

    test "falls back to extracted text when no summary exists" do
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Full extracted body about park improvements.",
        character_count: 44
      )

      ClassifyMatterThemes.call(matter: @matter, client: @client)

      assert_includes @client.last_user_prompt, "Full extracted body about park improvements."
    end

    test "classifies from identifiers alone when there is no attachment text" do
      result = ClassifyMatterThemes.call(matter: @matter, client: @client)

      assert_equal "succeeded", result.artifact.status
      assert_includes @client.last_user_prompt, Prompts::MatterThemesV1::NO_BODY_TEXT
    end

    test "is idempotent for the same input, prompt, and model" do
      add_summary(summary: "Housing project.", key_points: [])

      first = ClassifyMatterThemes.call(matter: @matter, client: @client)
      second = ClassifyMatterThemes.call(matter: @matter, client: @client)

      assert_equal first.artifact, second.artifact
      assert_equal true, second.skipped
      assert_equal 1, @client.calls
      assert_equal 1, Artifact.where(kind: "matter_themes").count
    end

    test "re-classifying replaces the projected themes" do
      add_summary(summary: "Housing project.", key_points: [])
      ClassifyMatterThemes.call(matter: @matter, client: @client)

      changed_client = FakeThemesClient.new(themes: [ "transportation" ])
      ClassifyMatterThemes.call(matter: @matter, client: changed_client, force: true)

      assert_equal [ "transportation" ], @matter.themes.pluck(:theme_slug)
    end

    test "empty theme set clears the projection" do
      add_summary(summary: "Procedural item.", key_points: [])
      ClassifyMatterThemes.call(matter: @matter, client: @client)
      assert_equal 2, @matter.themes.count

      empty_client = FakeThemesClient.new(themes: [])
      ClassifyMatterThemes.call(matter: @matter, client: empty_client, force: true)

      assert_equal 0, @matter.themes.count
    end

    test "client errors are captured on a failed artifact" do
      add_summary(summary: "Housing.", key_points: [])
      failing = FakeThemesClient.new(error: RuntimeError.new("budget exceeded"))

      result = ClassifyMatterThemes.call(matter: @matter, client: failing)

      assert_equal "failed", result.artifact.status
      assert_equal "budget exceeded", result.artifact.error_message
      assert_equal 0, @matter.themes.count
    end

    private

    def add_summary(summary:, key_points:)
      @attachment.generated_artifacts.create!(
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "summary-model",
        prompt_version: "attachment_summary_v3",
        input_sha256: Digest::SHA256.hexdigest(summary),
        content: { "summary" => summary, "key_points" => key_points, "limitations" => [], "document_status" => "final" }
      )
    end

    class FakeThemesClient
      attr_reader :calls, :model_name, :max_input_chars, :last_user_prompt

      def initialize(themes: [], error: nil)
        @themes = themes
        @error = error
        @calls = 0
        @model_name = "test-themes-model"
        @max_input_chars = 12_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        @last_user_prompt = user_prompt
        raise @error if @error

        ThemesClient::Response.new(
          model_name:,
          content: { "themes" => @themes },
          usage_metadata: { "total_tokens" => 42 }
        )
      end
    end
  end
end
