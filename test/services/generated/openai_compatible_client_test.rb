require "test_helper"

module Generated
  class OpenAICompatibleClientTest < ActiveSupport::TestCase
    class TestClient < OpenAICompatibleClient
      def initialize(api_key: "test-key", api_base: "https://api.example.com/v1", model_name: "test-model",
        timeout_seconds: 30, max_input_chars: 1000, temperature: 0.5, sleeper: nil)
        super
      end

      private

      def client_label
        "Test"
      end

      def normalize_content_shape(parsed_content)
        unless parsed_content.is_a?(Hash)
          raise RequestError, "Test model returned non-object JSON"
        end

        { "result" => parsed_content["result"].to_s.strip }
      end
    end

    def response_stub(code, body)
      stub = Object.new
      stub.define_singleton_method(:code) { code.to_s }
      stub.define_singleton_method(:message) { "" }
      stub.define_singleton_method(:body) { body }
      stub
    end

    def ok_response(content_hash)
      response_stub(200, {
        choices: [ { message: { content: content_hash.to_json } } ],
        usage: { total_tokens: 42 }
      }.to_json)
    end

    test "builds correct chat completions request" do
      captured_body = nil
      client = TestClient.new

      ok = response_stub(200, {
        choices: [ { message: { content: { result: "ok" }.to_json } } ],
        usage: {}
      }.to_json)

      client.define_singleton_method(:perform_http_request) do |_uri, request_body|
        captured_body = request_body
        ok
      end

      client.call(system_prompt: "be concise", user_prompt: "hello")

      body = JSON.parse(captured_body)
      assert_equal "test-model", body["model"]
      assert_equal "be concise", body["messages"][0]["content"]
      assert_equal "system", body["messages"][0]["role"]
      assert_equal "hello", body["messages"][1]["content"]
      assert_equal "user", body["messages"][1]["role"]
      assert_in_delta 0.5, body["temperature"]
      assert_equal({ "type" => "json_object" }, body["response_format"])
    end

    test "sets authorization and content-type headers" do
      captured_request = nil

      ok = response_stub(200, {
        choices: [ { message: { content: { result: "ok" }.to_json } } ],
        usage: {}
      }.to_json)

      client = TestClient.new

      client.define_singleton_method(:perform_http_request) do |uri, request_body|
        http = Object.new
        http.define_singleton_method(:use_ssl=) { |v| }
        http.define_singleton_method(:open_timeout=) { |v| }
        http.define_singleton_method(:read_timeout=) { |v| }
        http.define_singleton_method(:request) do |req|
          captured_request = req
          ok
        end

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = request_body
        http.request(request)
      end

      client.define_singleton_method(:build_request_body) do |system_prompt:, user_prompt:|
        "{}"
      end

      client.call(system_prompt: "sys", user_prompt: "usr")

      assert_equal "Bearer test-key", captured_request["Authorization"]
      assert_equal "application/json", captured_request["Content-Type"]
    end

    test "preserves usage_metadata" do
      client = TestClient.new
      ok = ok_response(result: "ok")

      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal({ "total_tokens" => 42 }, response.usage_metadata)
    end

    test "raises ConfigurationError when API key is blank" do
      client = TestClient.new(api_key: nil)
      assert_raises(OpenAICompatibleClient::ConfigurationError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end
    end

    test "raises ConfigurationError when API key is empty string" do
      client = TestClient.new(api_key: "")
      assert_raises(OpenAICompatibleClient::ConfigurationError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end
    end

    test "raises RequestError for non-retryable 4xx and does not retry" do
      call_count = 0
      client = TestClient.new
      err = response_stub(400, '{"error":{"message":"bad request"}}')

      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        err
      end

      error = assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_match(/Test request failed with status 400/, error.message)
      assert_equal 1, call_count
    end

    test "raises RequestError for 401 without retry" do
      call_count = 0
      client = TestClient.new
      err = response_stub(401, '{"error":{"message":"unauthorized"}}')

      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        err
      end

      assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_equal 1, call_count
    end

    test "raises RequestError for 403 without retry" do
      call_count = 0
      client = TestClient.new
      err = response_stub(403, '{"error":{"message":"forbidden"}}')

      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        err
      end

      assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_equal 1, call_count
    end

    test "retries on 429 and succeeds on second attempt" do
      call_count = 0
      err = response_stub(429, '{"error":{"message":"rate limited"}}')
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        call_count == 1 ? err : ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "retries on 503 and succeeds on second attempt" do
      call_count = 0
      err = response_stub(503, '{"error":{"message":"service unavailable"}}')
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        call_count == 1 ? err : ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "retries on 503 with non-JSON body and succeeds" do
      call_count = 0
      err = response_stub(503, "Service Unavailable")
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        call_count == 1 ? err : ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "retries on 429 with empty body and succeeds" do
      call_count = 0
      err = response_stub(429, "")
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        call_count == 1 ? err : ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "retries on 500 and succeeds on third attempt" do
      call_count = 0
      err1 = response_stub(500, '{"error":{"message":"internal error"}}')
      err2 = response_stub(502, '{"error":{"message":"bad gateway"}}')
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        case call_count
        when 1 then err1
        when 2 then err2
        else ok
        end
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 3, call_count
    end

    test "retries on Net::ReadTimeout and succeeds" do
      call_count = 0
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        raise Net::ReadTimeout if call_count == 1
        ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "retries on Net::OpenTimeout and succeeds" do
      call_count = 0
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        raise Net::OpenTimeout if call_count == 1
        ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "retries on Errno::ECONNRESET and succeeds" do
      call_count = 0
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        raise Errno::ECONNRESET if call_count == 1
        ok
      end

      response = client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal "ok", response.content["result"]
      assert_equal 2, call_count
    end

    test "stops after max attempts on persistent 429" do
      call_count = 0
      err = response_stub(429, '{"error":{"message":"rate limited"}}')

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        err
      end

      error = assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_match(/Test request failed after 3 attempts/, error.message)
      assert_equal 3, call_count
    end

    test "stops after max attempts on persistent network errors" do
      call_count = 0

      client = TestClient.new(sleeper: ->(secs) { })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        raise Errno::ECONNREFUSED
      end

      error = assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_match(/Test request failed after 3 attempts/, error.message)
      assert_equal 3, call_count
    end

    test "does not retry invalid endpoint JSON" do
      call_count = 0
      client = TestClient.new

      bad = Object.new
      bad.define_singleton_method(:code) { "200" }
      bad.define_singleton_method(:message) { "OK" }
      bad.define_singleton_method(:body) { "not valid json" }

      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        bad
      end

      error = assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_match(/Test endpoint returned invalid JSON/, error.message)
      assert_equal 1, call_count
    end

    test "does not retry invalid model JSON" do
      call_count = 0
      err = response_stub(200, {
        choices: [ { message: { content: "not valid json either" } } ],
        usage: {}
      }.to_json)

      client = TestClient.new
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        err
      end

      error = assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_match(/Test model returned invalid JSON/, error.message)
      assert_equal 1, call_count
    end

    test "does not retry malformed content shape" do
      call_count = 0
      err = response_stub(200, {
        choices: [ { message: { content: '"just a string"' } } ],
        usage: {}
      }.to_json)

      client = TestClient.new
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        call_count += 1
        err
      end

      error = assert_raises(OpenAICompatibleClient::RequestError) do
        client.call(system_prompt: "sys", user_prompt: "usr")
      end

      assert_match(/Test model returned non-object/, error.message)
      assert_equal 1, call_count
    end

    test "does not sleep in tests when sleeper is no-op" do
      sleeper_calls = []
      err = response_stub(429, '{"error":{"message":"rate limited"}}')
      ok = ok_response(result: "ok")

      client = TestClient.new(sleeper: ->(secs) { sleeper_calls << secs })
      client.define_singleton_method(:perform_http_request) do |_uri, _body|
        sleeper_calls.length < 2 ? err : ok
      end

      client.call(system_prompt: "sys", user_prompt: "usr")
      assert_equal [ 2, 4 ], sleeper_calls
    end

    test "exposes model_name and max_input_chars" do
      client = TestClient.new(model_name: "gpt-42", max_input_chars: 5000, temperature: 0.9)
      assert_equal "gpt-42", client.model_name
      assert_equal 5000, client.max_input_chars
      assert_in_delta 0.9, client.temperature
    end
  end
end
