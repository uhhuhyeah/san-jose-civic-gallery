require "test_helper"

module Generated
  class BackfillMatterThemesTest < ActiveSupport::TestCase
    setup do
      @client = FakeThemesClient.new(themes: [ "housing" ])
    end

    test "dry run reports candidate matters without calling the model" do
      a = matter(70_001, "26-400")
      b = matter(70_002, "26-401")

      result = BackfillMatterThemes.call(limit: 10, dry_run: true, client: @client)

      assert_equal [ a.id, b.id ], result.candidates.map(&:id)
      assert_equal 0, result.generated
      assert_equal 0, @client.calls
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

    test "respects the limit" do
      matter(70_005, "26-404")
      matter(70_006, "26-405")

      result = BackfillMatterThemes.call(limit: 1, dry_run: true, client: @client)

      assert_equal 1, result.candidates.size
    end

    private

    def matter(legistar_id, file)
      Civic::Matter.create!(legistar_matter_id: legistar_id, matter_file: file)
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
