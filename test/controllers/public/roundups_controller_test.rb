require "test_helper"

module Public
  class RoundupsControllerTest < ActionDispatch::IntegrationTest
    setup do
      Civic::Jurisdiction.seed_defaults!
      @jurisdiction = Civic::Jurisdiction.default
      @period = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)
      @matter = Civic::Matter.create!(
        legistar_matter_id: 90_900,
        matter_file: "26-950",
        title: "Affordable housing agreement",
        passed_date: Date.new(2026, 5, 15),
        source_system: "legistar.sanjose"
      )
      Generated::Artifact.create!(
        target: @period,
        kind: Generated::SummarizeRoundup::KIND,
        model_identifier: "test",
        prompt_version: Generated::Prompts::MonthlyRoundupV1::VERSION,
        input_sha256: "test-sha",
        status: "succeeded",
        generated_at: Time.current,
        content: {
          "headline" => "May in San Jose",
          "intro" => "A short intro.",
          "storyline" => "The housing story."
        }
      )
    end

    test "index lists periods with artifacts" do
      get roundups_path

      assert_response :success
      assert_includes response.body, "May 2026"
      assert_select "a[href=?]", roundup_path(@period)
    end

    test "show displays the roundup content" do
      get roundup_path(@period)

      assert_response :success
      assert_includes response.body, "May in San Jose"
      assert_includes response.body, "The housing story."
      assert_includes response.body, "26-950"
      assert_select "a[href=?]", public_matter_path(@matter)
    end

    test "show returns 404 when period has no roundup artifact" do
      @no_artifact_period = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 4)

      get roundup_path(@no_artifact_period)

      assert_response :not_found
    end

    test "show returns 404 for malformed period param" do
      get "/roundups/not-a-month"

      assert_response :not_found
    end

    test "homepage links to roundups" do
      get root_path

      assert_response :success
      assert_select "a[href=?]", roundups_path
    end

    # ---- Atlas redesign acceptance ----

    test "roundups index renders inside the Atlas shell" do
      get roundups_path

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
      assert_select "header.atlas-roundups-header h1"
      assert_select "a.atlas-roundup-period-card[href=?]", roundup_path(@period) do
        assert_select ".atlas-roundup-period-label", text: /May 2026/
      end
    end

    test "roundup show renders the Atlas storyline and decision list" do
      @matter.themes.create!(theme_slug: "housing", rank: 1) if @matter.themes.empty?
      Civic::Event.create!(legistar_event_id: 991_001, body_name: "City Council", event_date: Date.new(2026, 5, 14)).event_items.create!(
        legistar_event_item_id: 991_500,
        civic_matter_id: @matter.id,
        matter_id: @matter.legistar_matter_id,
        agenda_sequence: 1,
        agenda_number: "1.",
        title: "Approve housing agreement"
      )

      get roundup_path(@period)

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "header.atlas-roundup-hero h1", text: "May in San Jose"
      assert_select "section.atlas-roundup-storyline"
      # The matter shows up in the "Decisions made" list — code chip + linked title.
      assert_select ".atlas-roundup-item .atlas-roundup-item-code", text: "26-950"
      assert_select ".atlas-roundup-item-title a[href=?]", public_matter_path(@matter)
    end
  end
end
