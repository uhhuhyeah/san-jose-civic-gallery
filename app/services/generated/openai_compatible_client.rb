require "json"
require "net/http"
require "uri"

module Generated
  class OpenAICompatibleClient
    Response = Data.define(:content, :model_name, :usage_metadata)

    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    DEFAULT_API_BASE = "https://api.openai.com/v1"
    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_TIMEOUT_SECONDS = 30
    MAX_RETRIES = 3

    attr_reader :model_name, :max_input_chars, :temperature

    def initialize(api_key:, api_base:, model_name:, timeout_seconds:, max_input_chars:, temperature:, sleeper: nil)
      @api_key = api_key
      @api_base = api_base
      @model_name = model_name
      @timeout_seconds = timeout_seconds
      @max_input_chars = max_input_chars
      @temperature = temperature
      @sleeper = sleeper || method(:sleep)
    end

    def call(system_prompt:, user_prompt:)
      raise ConfigurationError, "GENERATED_SUMMARY_API_KEY is required" if @api_key.blank?

      response = post_chat_completion(system_prompt:, user_prompt:)
      raw_content = response.dig("choices", 0, "message", "content").to_s
      parsed_content = JSON.parse(raw_content)
      normalized_content = normalize_content_shape(parsed_content)

      Response.new(content: normalized_content, model_name:, usage_metadata: response.fetch("usage", {}))
    rescue JSON::ParserError => error
      raise RequestError, "#{client_label} model returned invalid JSON: #{error.message}"
    end

    private

    def post_chat_completion(system_prompt:, user_prompt:)
      uri = URI.join(@api_base.end_with?("/") ? @api_base : "#{@api_base}/", "chat/completions")
      request_body = build_request_body(system_prompt:, user_prompt:)

      last_error = nil
      MAX_RETRIES.times do |attempt|
        @sleeper.call(backoff_seconds(attempt)) if attempt > 0

        begin
          response = perform_http_request(uri, request_body)
          status = response.code.to_i

          if status >= 400
            if retryable_response?(status)
              last_error = RequestError.new("#{client_label} request failed with status #{status}: #{error_message(response)}")
              next
            else
              raise RequestError, "#{client_label} request failed with status #{status}: #{error_message(response)}"
            end
          end

          body = JSON.parse(response.body)
          return body
        rescue Net::OpenTimeout, Net::ReadTimeout,
               Errno::ECONNRESET, Errno::ECONNREFUSED,
               Errno::EHOSTUNREACH, Errno::ENETUNREACH,
               SocketError, EOFError, Timeout::Error => e
          last_error = e
        rescue JSON::ParserError => e
          raise RequestError, "#{client_label} endpoint returned invalid JSON: #{e.message}"
        end
      end

      raise RequestError, "#{client_label} request failed after #{MAX_RETRIES} attempts: #{last_error.message}"
    end

    def error_message(response)
      body = JSON.parse(response.body) rescue nil
      body&.dig("error", "message").presence || response.message
    end

    def perform_http_request(uri, request_body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = request_body

      http.request(request)
    end

    def build_request_body(system_prompt:, user_prompt:)
      {
        model: @model_name,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ],
        temperature: @temperature,
        response_format: { type: "json_object" }
      }.to_json
    end

    def retryable_response?(status)
      status == 429 || status.between?(500, 599)
    end

    def backoff_seconds(attempt)
      2 ** attempt
    end

    def client_label
      raise NotImplementedError
    end

    def normalize_content_shape(parsed_content)
      raise NotImplementedError
    end
  end
end
