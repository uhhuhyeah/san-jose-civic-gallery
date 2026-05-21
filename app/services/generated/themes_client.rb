require "json"
require "net/http"
require "uri"

module Generated
  # ThemesClient calls an OpenAI-compatible /chat/completions endpoint and
  # returns the matter themes selected by the model. It honors the same
  # duck-typed contract as SummaryClient (call/model_name/max_input_chars) so
  # the classification service can accept a fake in tests.
  #
  # Provider credentials are shared with the summary client (same endpoint);
  # only the model and limits are themes-specific.
  class ThemesClient
    Response = Data.define(:content, :model_name, :usage_metadata)

    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    DEFAULT_API_BASE = "https://api.openai.com/v1"
    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_TIMEOUT_SECONDS = 30

    attr_reader :model_name, :max_input_chars

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_THEMES_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_THEMES_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      max_input_chars: ENV.fetch("GENERATED_THEMES_MAX_INPUT_CHARS", Generated::Prompts::MatterThemesBase::DEFAULT_MAX_INPUT_CHARS).to_i
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
      normalized_content = normalize_content_shape(parsed_content)

      Response.new(content: normalized_content, model_name:, usage_metadata: response.fetch("usage", {}))
    rescue JSON::ParserError => error
      raise RequestError, "Themes model returned invalid JSON: #{error.message}"
    end

    private

    attr_reader :api_key, :api_base, :timeout_seconds

    # Validate only the response shape. The taxonomy is per-jurisdiction and the
    # client does not know the matter, so filtering returned slugs against the
    # vocabulary is the caller's job (Generated::ClassifyMatterThemes#valid_slugs).
    # A missing "themes" key is malformed and does raise.
    def normalize_content_shape(parsed_content)
      unless parsed_content.is_a?(Hash) && parsed_content.key?("themes")
        raise RequestError, "Themes model response must be an object with a \"themes\" array"
      end

      { "themes" => Array(parsed_content["themes"]).flatten.map(&:to_s) }
    end

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
        temperature: 0.0,
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
        raise RequestError, "Themes request failed with status #{response.code}: #{message}"
      end

      body
    rescue JSON::ParserError => error
      raise RequestError, "Themes endpoint returned invalid JSON: #{error.message}"
    end
  end
end
