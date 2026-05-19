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

    test "links to glossary from primary navigation and footer" do
      get root_url

      assert_response :success
      assert_includes response.body, glossary_path
      assert_includes response.body, "Glossary"
    end
  end
end
