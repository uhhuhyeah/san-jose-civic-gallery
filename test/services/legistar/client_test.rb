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
        assert_match(/SanJoseCivicPulse/, captured_request["User-Agent"])
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
  end
end
