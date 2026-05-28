require "json"
require "net/http"
require "uri"

module Generated
  # RoundupClient calls an OpenAI-compatible /chat/completions endpoint and
  # returns the parsed monthly roundup. It honors the same duck-typed contract as
  # EventSummaryClient (call/model_name/max_input_chars).
  #
  # Provider credentials are shared with the other generated clients (same
  # endpoint); only the model, limits, and required content keys differ.
  class RoundupClient
    Response = Data.define(:content, :model_name, :usage_metadata)

    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    DEFAULT_API_BASE = "https://api.openai.com/v1"
    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_TIMEOUT_SECONDS = 30
    # Warmer than the factual summary clients (which use 0.1): the roundup is
    # narrative prose, so a little more variation reads less flat. Overridable via
    # ENV so it can be tuned in production without a redeploy. The Layer-1 facts
    # remain the hallucination firewall regardless of temperature.
    DEFAULT_TEMPERATURE = 0.6
    REQUIRED_CONTENT_KEYS = %w[headline intro storyline].freeze

    attr_reader :model_name, :max_input_chars, :temperature

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_ROUNDUP_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_ROUNDUP_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      temperature: ENV.fetch("GENERATED_ROUNDUP_TEMPERATURE", DEFAULT_TEMPERATURE).to_f,
      max_input_chars: ENV.fetch("GENERATED_ROUNDUP_MAX_INPUT_CHARS", Generated::Prompts::MonthlyRoundupV1::DEFAULT_MAX_INPUT_CHARS).to_i
    )
      @api_key = api_key
      @api_base = api_base
      @model_name = model_name
      @timeout_seconds = timeout_seconds
      @temperature = temperature
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
      raise RequestError, "Roundup model returned invalid JSON: #{error.message}"
    end

    private

    attr_reader :api_key, :api_base, :timeout_seconds

    def normalize_content_shape(parsed_content)
      unless parsed_content.is_a?(Hash)
        raise RequestError, "Roundup model returned non-object JSON; expected an object with keys #{REQUIRED_CONTENT_KEYS.join(', ')}"
      end

      missing = REQUIRED_CONTENT_KEYS - parsed_content.keys
      unless missing.empty?
        raise RequestError, "Roundup model response is missing required keys: #{missing.join(', ')}"
      end

      normalized = parsed_content.slice(*REQUIRED_CONTENT_KEYS)
      normalized["headline"] = normalized["headline"].to_s.strip
      normalized["intro"] = normalized["intro"].to_s.strip
      normalized["storyline"] = normalized["storyline"].to_s.strip
      normalized["highlights"] = normalize_strings(parsed_content["highlights"])
      normalized["decision_blurbs"] = normalize_blurbs(parsed_content["decision_blurbs"])
      normalized
    end

    # highlights is optional model output: an array of short scannable bullet
    # strings. Coerce to stripped, non-blank strings; default to an empty array.
    def normalize_strings(value)
      Array(value).map { |item| item.to_s.strip }.reject(&:blank?)
    end

    # decision_blurbs is optional model output: an array of { matter_file, blurb }
    # objects. We keep only well-formed entries (both fields present) so the view
    # can match each blurb back to a real Layer-1 decision by matter_file. Anything
    # malformed is dropped rather than raising; the blurbs are decoration, and the
    # authoritative decision list comes from the database, not the model.
    def normalize_blurbs(value)
      Array(value).filter_map do |entry|
        next unless entry.is_a?(Hash)

        matter_file = entry["matter_file"].to_s.strip
        blurb = entry["blurb"].to_s.strip
        next if matter_file.blank? || blurb.blank?

        { "matter_file" => matter_file, "blurb" => blurb }
      end
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
        temperature: temperature,
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
        raise RequestError, "Roundup request failed with status #{response.code}: #{message}"
      end

      body
    rescue JSON::ParserError => error
      raise RequestError, "Roundup endpoint returned invalid JSON: #{error.message}"
    end
  end
end
