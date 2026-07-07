module Generated
  # EventSummaryClient calls an OpenAI-compatible /chat/completions
  # endpoint and returns the parsed event summary. It honors the same
  # duck-typed contract as SummaryClient and ThemesClient
  # (call/model_name/max_input_chars) so SummarizeEvent can accept a
  # fake in tests.
  #
  # Provider credentials are shared with the other generated clients
  # (same endpoint); model, limits, and required content keys differ.
  class EventSummaryClient < OpenAICompatibleClient
    Response = OpenAICompatibleClient::Response
    ConfigurationError = OpenAICompatibleClient::ConfigurationError
    RequestError = OpenAICompatibleClient::RequestError

    DEFAULT_MODEL = "gpt-4o-mini"
    REQUIRED_CONTENT_KEYS = %w[summary key_topics limitations].freeze

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_EVENT_SUMMARY_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_EVENT_SUMMARY_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      max_input_chars: ENV.fetch("GENERATED_EVENT_SUMMARY_MAX_INPUT_CHARS", Generated::Prompts::EventSummaryV1::DEFAULT_MAX_INPUT_CHARS).to_i,
      temperature: 0.1,
      sleeper: nil
    )
      super(api_key:, api_base:, model_name:, timeout_seconds:, max_input_chars:, temperature:, sleeper:)
    end

    private

    def client_label
      "Event summary"
    end

    def normalize_content_shape(parsed_content)
      unless parsed_content.is_a?(Hash)
        raise RequestError, "Event summary model returned non-object JSON; expected an object with keys #{REQUIRED_CONTENT_KEYS.join(', ')}"
      end

      missing = REQUIRED_CONTENT_KEYS - parsed_content.keys
      unless missing.empty?
        raise RequestError, "Event summary model response is missing required keys: #{missing.join(', ')}"
      end

      normalized = parsed_content.slice(*REQUIRED_CONTENT_KEYS)
      normalized["summary"] = normalized["summary"].to_s.strip
      normalized["key_topics"] = normalize_string_array(normalized["key_topics"])
      normalized["limitations"] = normalize_string_array(normalized["limitations"])
      normalized
    end

    def normalize_string_array(value)
      Array(value)
        .flatten
        .map { |item| item.to_s.strip }
        .reject(&:blank?)
    end
  end
end
