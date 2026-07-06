module Generated
  # SummaryClient calls an OpenAI-compatible /chat/completions endpoint
  # and returns a parsed JSON Response. Alternate clients (fakes for
  # tests, alternative providers) must honor the same duck-typed contract:
  #
  #   - call(system_prompt:, user_prompt:) -> Response
  #   - model_name        -> String, used for provenance and idempotency
  #   - max_input_chars   -> Integer, used by the prompt builder to
  #                          truncate extracted text before sending
  #
  # The returned Response must expose:
  #   - content        -> Hash with keys from REQUIRED_CONTENT_KEYS
  #   - model_name     -> String matching the calling client's model_name
  #   - usage_metadata -> Hash of provider usage fields
  class SummaryClient < OpenAICompatibleClient
    Response = OpenAICompatibleClient::Response
    ConfigurationError = OpenAICompatibleClient::ConfigurationError
    RequestError = OpenAICompatibleClient::RequestError

    DEFAULT_MODEL = "gpt-4o-mini"
    REQUIRED_CONTENT_KEYS = %w[summary key_points limitations document_status].freeze
    DOCUMENT_STATUSES = %w[draft final unknown].freeze

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_SUMMARY_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_SUMMARY_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      max_input_chars: ENV.fetch("GENERATED_SUMMARY_MAX_INPUT_CHARS", Generated::Prompts::AttachmentSummaryV1::DEFAULT_MAX_INPUT_CHARS).to_i,
      temperature: 0.2,
      sleeper: nil
    )
      super(api_key:, api_base:, model_name:, timeout_seconds:, max_input_chars:, temperature:, sleeper:)
    end

    private

    def client_label
      "Summary"
    end

    def normalize_content_shape(parsed_content)
      unless parsed_content.is_a?(Hash)
        raise RequestError, "Summary model returned non-object JSON; expected an object with keys #{REQUIRED_CONTENT_KEYS.join(', ')}"
      end

      missing = REQUIRED_CONTENT_KEYS - parsed_content.keys
      unless missing.empty?
        raise RequestError, "Summary model response is missing required keys: #{missing.join(', ')}"
      end

      normalized = parsed_content.slice(*REQUIRED_CONTENT_KEYS)
      normalized["summary"] = normalized["summary"].to_s.strip
      normalized["key_points"] = normalize_string_array(normalized["key_points"])
      normalized["limitations"] = normalize_string_array(normalized["limitations"])
      normalized["document_status"] = normalize_document_status(normalized["document_status"])
      normalized
    end

    def normalize_string_array(value)
      Array(value)
        .flatten
        .map { |item| item.to_s.strip }
        .reject(&:blank?)
    end

    def normalize_document_status(value)
      status = value.to_s.downcase.strip
      DOCUMENT_STATUSES.include?(status) ? status : "unknown"
    end
  end
end
