require "test_helper"

module Public
  class GlossaryControllerTest < ActionDispatch::IntegrationTest
    test "shows the public glossary with source citations" do
      get glossary_url

      assert_response :success
      assert_includes response.body, "Plain-language guide to City Hall records"
      assert_includes response.body, "Is a report a matter or an attachment?"
      assert_includes response.body, "follows the City"
      assert_includes response.body, "Legistar provides the connection"
      assert_includes response.body, "Matter"
      assert_includes response.body, "Minutes"
      assert_includes response.body, "Generated Summary"
      assert_includes response.body, "Sources"
      assert_includes response.body, "City of San Jose Office of the City Clerk"
      assert_includes response.body, "California Government Code Section 54954.2"
      assert_includes response.body, "Legistar Web API"
    end

    test "shows the Board of Education glossary on the SJUSD host" do
      host! "sjusd.civicgallery.org"
      get glossary_url

      assert_response :success
      assert_includes response.body, "Plain-language guide to Board of Education records"
      assert_includes response.body, "Consent Calendar"
      assert_includes response.body, "Board Policy"
      assert_includes response.body, "Administrative Regulation"
      assert_includes response.body, "California School Boards Association"
      assert_includes response.body, "San José Unified Board of Education"
      # Shared terms section is still present.
      assert_includes response.body, "Generated Summary"
      # City-government copy must not leak onto the district host.
      assert_not_includes response.body, "Plain-language guide to City Hall records"
      assert_not_includes response.body, "Office of the City Clerk"
    end

    test "shows the Board of Supervisors glossary on the Santa Clara County host" do
      host! "santaclaracounty.civicgallery.org"
      get glossary_url

      assert_response :success
      assert_includes response.body, "Plain-language guide to Board of Supervisors records"
      assert_includes response.body, "Consent Calendar"
      assert_includes response.body, "Board Referral"
      assert_includes response.body, "Off-Agenda Report"
      assert_includes response.body, "Legislative File (LegiFile)"
      assert_includes response.body, "Santa Clara County Legislative Portal"
      # Shared terms section is still present.
      assert_includes response.body, "Generated Summary"
      # City-government and school-district copy must not leak onto the county host.
      assert_not_includes response.body, "Plain-language guide to City Hall records"
      assert_not_includes response.body, "Office of the City Clerk"
      assert_not_includes response.body, "Board of Education"
    end

    test "links to glossary from primary navigation and footer" do
      get root_url

      assert_response :success
      assert_includes response.body, glossary_path
      assert_includes response.body, "Glossary"
    end

    test "glossary page renders inside the Atlas shell" do
      get glossary_url

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
      assert_select "header.atlas-glossary-header h1"
      assert_select "section.atlas-glossary-section"
      assert_select "article.atlas-glossary-term", minimum: 5
    end
  end
end
