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
  end
end
