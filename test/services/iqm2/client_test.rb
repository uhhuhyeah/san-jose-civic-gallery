require "test_helper"

module Iqm2
  class ClientTest < ActiveSupport::TestCase
    test "meeting_listing issues GET with User-Agent and text/html Accept, returns raw body as payload" do
      captured_request = nil

      original_start = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req

          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.instance_variable_set(:@__body, "<rss/>")
          response.define_singleton_method(:body) { @__body }
          response.define_singleton_method(:code) { "200" }
          response
        end
        block.call(fake_http)
      end

      begin
        result = Client.new.meeting_listing

        assert_equal "<rss/>", result[:payload]
        assert_equal 200, result[:status]
        assert result[:response_sha256].present?
        assert_equal "text/html", captured_request["Accept"]
        assert_match(/SanJoseCivicGallery/, captured_request["User-Agent"])
        assert_includes result[:request_url], "RSS.aspx"
        assert_includes result[:request_url], "Feed=Calendar"
      ensure
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end

    test "meeting_detail targets Detail_Meeting.aspx with the ID param" do
      captured_uri = nil

      original_start = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_uri = req.uri

          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.define_singleton_method(:body) { "<html/>" }
          response.define_singleton_method(:code) { "200" }
          response
        end
        block.call(fake_http)
      end

      begin
        Client.new.meeting_detail(meeting_id: "17599")

        assert_includes captured_uri.to_s, "Detail_Meeting.aspx"
        assert_includes captured_uri.to_s, "ID=17599"
      ensure
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end

    test "calendar builds a US-formatted date window" do
      captured_uri = nil

      original_start = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_uri = req.uri

          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.define_singleton_method(:body) { "<html/>" }
          response.define_singleton_method(:code) { "200" }
          response
        end
        block.call(fake_http)
      end

      begin
        Client.new.calendar(from: Date.new(2026, 1, 5), to: Date.new(2026, 2, 10))

        params = Rack::Utils.parse_nested_query(captured_uri.query)
        assert_equal "1/5/2026", params["From"]
        assert_equal "2/10/2026", params["To"]
        assert_equal "List", params["View"]
      ensure
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end
  end
end
