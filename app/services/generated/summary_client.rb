require "json"
require "net/http"
require "uri"

module Generated
  class SummaryClient
    Response = Data.define(:content, :model_name)

    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    DEFAULT_API_BASE = "https://api.openai.com/v1"
    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_TIMEOUT_SECONDS = 30

    attr_reader :model_name, :max_input_chars

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_SUMMARY_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_SUMMARY_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      max_input_chars: ENV.fetch("GENERATED_SUMMARY_MAX_INPUT_CHARS", Generated::Prompts::AttachmentSummaryV1::DEFAULT_MAX_INPUT_CHARS).to_i
    )
      @api_key = api_key
      @api_base = api_base
      @model_name = model_name
      @timeout_seconds = timeout_seconds
      @max_input_chars = max_input_chars
    end

    def call(system_prompt:, user_prompt:)
      raise ConfigurationError, "GENERATED_SUMMARY_API_KEY is required" if api_key.blank?

      response = post_chat_completion(system_prompt:, user_prompt:)
      raw_content = response.dig("choices", 0, "message", "content").to_s
      parsed_content = JSON.parse(raw_content)

      Response.new(content: parsed_content, model_name:)
    rescue JSON::ParserError => error
      raise RequestError, "Summary model returned invalid JSON: #{error.message}"
    end

    private

    attr_reader :api_key, :api_base, :timeout_seconds

    def post_chat_completion(system_prompt:, user_prompt:)
      uri = URI.join(api_base.end_with?("/") ? api_base : "#{api_base}/", "chat/completions")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = {
        model: model_name,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ],
        temperature: 0.2,
        response_format: { type: "json_object" }
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout_seconds
      http.read_timeout = timeout_seconds

      response = http.request(request)
      body = JSON.parse(response.body)

      if response.code.to_i >= 400
        message = body.dig("error", "message").presence || response.message
        raise RequestError, "Summary request failed with status #{response.code}: #{message}"
      end

      body
    rescue JSON::ParserError => error
      raise RequestError, "Summary endpoint returned invalid JSON: #{error.message}"
    end
  end
end
