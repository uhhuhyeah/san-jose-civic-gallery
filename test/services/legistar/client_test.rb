require "test_helper"

module Legistar
  class ClientTest < ActiveSupport::TestCase
    test "issues GET with timeouts, User-Agent, and Accept headers" do
      captured_args = nil
      captured_kwargs = nil
      captured_request = nil

      original_start = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        captured_args = args
        captured_kwargs = kwargs

        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req

          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.instance_variable_set(:@__body, '[{"EventId":1}]')
          response.define_singleton_method(:body) { @__body }
          response.define_singleton_method(:code) { "200" }
          response
        end
        block.call(fake_http)
      end

      begin
        result = Client.new.event_items(event_id: 7622)

        assert_equal "webapi.legistar.com", captured_args[0]
        assert_equal 443, captured_args[1]
        assert_equal true, captured_kwargs[:use_ssl]
        assert_equal 5, captured_kwargs[:open_timeout]
        assert_equal 30, captured_kwargs[:read_timeout]
        assert_match(/SanJoseCivicGallery/, captured_request["User-Agent"])
        assert_equal "application/json", captured_request["Accept"]
        assert_equal 200, result[:status]
        assert_equal [ { "EventId" => 1 } ], result[:payload]
      ensure
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end

    test "reads LEGISTAR_API_BASE_URL per call" do
      ENV["LEGISTAR_API_BASE_URL"] = "https://example.test/api"
      captured_host = nil

      original_start = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |host, *_args, **_kwargs, &block|
        captured_host = host
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |_req|
          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.define_singleton_method(:body) { "[]" }
          response.define_singleton_method(:code) { "200" }
          response
        end
        block.call(fake_http)
      end

      begin
        Client.new.event_items(event_id: 1)
        assert_equal "example.test", captured_host
      ensure
        ENV.delete("LEGISTAR_API_BASE_URL")
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end

    test "respects LEGISTAR_OPEN_TIMEOUT and LEGISTAR_READ_TIMEOUT env vars" do
      ENV["LEGISTAR_OPEN_TIMEOUT"] = "2"
      ENV["LEGISTAR_READ_TIMEOUT"] = "60"
      captured_kwargs = nil

      original_start = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*_args, **kwargs, &block|
        captured_kwargs = kwargs
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |_req|
          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.define_singleton_method(:body) { "[]" }
          response.define_singleton_method(:code) { "200" }
          response
        end
        block.call(fake_http)
      end

      begin
        Client.new.event_items(event_id: 1)
        assert_equal 2, captured_kwargs[:open_timeout]
        assert_equal 60, captured_kwargs[:read_timeout]
      ensure
        ENV.delete("LEGISTAR_OPEN_TIMEOUT")
        ENV.delete("LEGISTAR_READ_TIMEOUT")
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end

    test "builds bounded event window query with OData datetime literals" do
      client = Client.new
      captured_uri = nil
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) { "[]" }
      original_start = Net::HTTP.method(:start)

      Net::HTTP.define_singleton_method(:start) do |host, port, **kwargs, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |request|
          captured_uri = request.uri
          response
        end
        block.call(fake_http)
      end

      result = client.events_for_window(
        body_name: "Mayor's Office",
        start_date: Date.new(2026, 5, 1),
        end_date: Date.new(2026, 6, 1),
        limit: 50,
        skip: 100
      )

      params = Rack::Utils.parse_nested_query(captured_uri.query)
      assert_equal 200, result[:status]
      assert_equal "EventBodyName eq 'Mayor''s Office' and EventDate ge datetime'2026-05-01T00:00:00' and EventDate lt datetime'2026-06-01T00:00:00'",
        params.fetch("$filter")
      assert_equal "EventDate asc, EventId asc", params.fetch("$orderby")
      assert_equal "50", params.fetch("$top")
      assert_equal "100", params.fetch("$skip")
    ensure
      Net::HTTP.singleton_class.send(:remove_method, :start)
      Net::HTTP.define_singleton_method(:start, original_start)
    end
  end
end
