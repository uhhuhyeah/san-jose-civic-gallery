require "test_helper"

module Generated
  class BackfillMatterThemesTest < ActiveSupport::TestCase
    setup do
      @client = FakeThemesClient.new(themes: [ "housing" ])
    end

    test "dry run reports candidate matters newest-agendized first, without calling the model" do
      older = matter(70_001, "26-400", agenda_date: Date.new(2026, 1, 1))
      newer = matter(70_002, "26-401", agenda_date: Date.new(2026, 5, 1))

      result = BackfillMatterThemes.call(limit: 10, dry_run: true, client: @client)

      assert_equal [ newer.id, older.id ], result.candidates.map(&:id)
      assert_equal 0, result.generated
      assert_equal 0, @client.calls
    end

    test "orders candidates by recency with never-agendized matters last" do
      recent = matter(80_001, "26-410", agenda_date: Date.new(2026, 5, 10))
      old = matter(80_002, "26-411", agenda_date: Date.new(2025, 5, 10))
      undated = matter(80_003, "26-412")

      result = BackfillMatterThemes.call(limit: 10, dry_run: true, client: @client)

      assert_equal [ recent.id, old.id, undated.id ], result.candidates.map(&:id)
    end

    test "generate mode classifies candidates" do
      matter(70_003, "26-402")

      result = BackfillMatterThemes.call(limit: 10, dry_run: false, client: @client)

      assert_equal 1, result.generated
      assert_equal 1, Artifact.succeeded.where(kind: "matter_themes").count
    end

    test "skips already classified matters unless forced" do
      candidate = matter(70_004, "26-403")
      ClassifyMatterThemes.call(matter: candidate, client: @client)

      result = BackfillMatterThemes.call(limit: 10, dry_run: true, client: @client)
      forced = BackfillMatterThemes.call(limit: 10, dry_run: true, client: @client, force: true)

      assert_empty result.candidates
      assert_equal [ candidate.id ], forced.candidates.map(&:id)
    end

    test "includes previously classified matters when the source input changed" do
      candidate = matter(70_007, "26-406")
      ClassifyMatterThemes.call(matter: candidate, client: @client)

      add_summary(candidate, summary: "Discusses a new protected bikeway network.")

      result = BackfillMatterThemes.call(limit: 10, dry_run: true, client: @client)

      assert_equal [ candidate.id ], result.candidates.map(&:id)
      assert_equal 1, @client.calls
    end

    test "respects the limit" do
      matter(70_005, "26-404")
      matter(70_006, "26-405")

      result = BackfillMatterThemes.call(limit: 1, dry_run: true, client: @client)

      assert_equal 1, result.candidates.size
    end

    private

    def matter(legistar_id, file, agenda_date: nil)
      Civic::Matter.create!(legistar_matter_id: legistar_id, matter_file: file, agenda_date:)
    end

    def add_summary(matter, summary:)
      attachment = matter.all_attachments.create!(
        legistar_matter_attachment_id: matter.legistar_matter_id + 10_000,
        name: "Staff report"
      )
      attachment.generated_artifacts.create!(
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "summary-model",
        prompt_version: "attachment_summary_v3",
        input_sha256: Digest::SHA256.hexdigest(summary),
        content: { "summary" => summary, "key_points" => [], "limitations" => [], "document_status" => "final" }
      )
      matter.reload
    end

    class FakeThemesClient
      attr_reader :calls, :model_name, :max_input_chars

      def initialize(themes: [])
        @themes = themes
        @calls = 0
        @model_name = "test-themes-model"
        @max_input_chars = 12_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        ThemesClient::Response.new(model_name:, content: { "themes" => @themes }, usage_metadata: {})
      end
    end
  end
end
