require "test_helper"

module Public
  class DiscoveryControllerTest < ActionDispatch::IntegrationTest
    SANJOSE_HOST = "sanjose.civicgallery.org".freeze
    SJUSD_HOST = "sjusd.civicgallery.org".freeze

    test "robots.txt is valid standard crawler guidance with a host-scoped sitemap" do
      host! SANJOSE_HOST

      get "/robots.txt"

      assert_response :success
      assert_equal "text/plain", response.media_type
      assert_includes response.body, "User-agent: *"
      assert_includes response.body, "Allow: /"
      assert_includes response.body, "Disallow: /jobs"
      assert_includes response.body, "Sitemap: http://#{SANJOSE_HOST}/sitemap.xml"
      assert_not_includes response.body, "Content-Signal"
      assert_no_match(/^LLMs:/, response.body)
    end

    test "llms.txt describes source boundaries for the current jurisdiction" do
      host! SJUSD_HOST

      get "/llms.txt"

      assert_response :success
      assert_equal "text/plain", response.media_type
      assert_includes response.body, "# San Jose Unified Civic Gallery"
      assert_includes response.body, "Official public records are authoritative"
      assert_includes response.body, "simbli.eboardsolutions.com"
      assert_not_includes response.body, "sanjose.legistar.com"
    end

    test "sitemap.xml includes only the current host's jurisdiction records" do
      sanjose_event = Civic::Event.create!(
        legistar_event_id: 97_001,
        body_name: "City Council",
        title: "San Jose Council Meeting",
        event_date: Date.current
      )
      sjusd_event = Civic::Event.create!(
        source_system: "simbli.sjusd",
        source_event_id: "sjusd-evt-sitemap",
        body_name: "Board of Education",
        title: "SJUSD Board Meeting",
        event_date: Date.current
      )
      sanjose_matter = Civic::Matter.create!(legistar_matter_id: 97_101, matter_file: "26-971")
      sjusd_matter = Civic::Matter.create!(
        source_system: "simbli.sjusd",
        source_matter_id: "sjusd:sitemap:1",
        matter_file: "SJUSD-971"
      )

      host! SJUSD_HOST
      get "/sitemap.xml"

      assert_response :success
      assert_equal "application/xml", response.media_type
      assert_includes response.body, "http://#{SJUSD_HOST}/"
      assert_includes response.body, public_event_url(sjusd_event)
      assert_includes response.body, public_matter_url(sjusd_matter)
      assert_not_includes response.body, public_event_url(sanjose_event)
      assert_not_includes response.body, public_matter_url(sanjose_matter)
    end

    test "public pages emit canonical and social metadata" do
      host! SANJOSE_HOST

      get public_matters_url(q: "housing")

      assert_response :success
      assert_select "link[rel='canonical'][href='http://#{SANJOSE_HOST}/public/matters']"
      assert_select "meta[property='og:url'][content='http://#{SANJOSE_HOST}/public/matters']"
      assert_select "meta[name='robots'][content='noindex,follow']"
      assert_select "meta[name='twitter:card'][content='summary']"
    end
  end
end
