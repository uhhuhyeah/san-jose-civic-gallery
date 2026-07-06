module Generated
  # RoundupClient calls an OpenAI-compatible /chat/completions endpoint
  # and returns the parsed monthly roundup. It honors the same duck-typed
  # contract as EventSummaryClient (call/model_name/max_input_chars) so
  # SummarizeMonthlyRoundup can accept a fake in tests.
  #
  # Provider credentials are shared with the other generated clients; only
  # the model, limits, and required content keys differ. Temperature is
  # warmer than the factual summary clients (which use 0.1) because the
  # roundup is narrative prose and a little more variation reads less flat.
  # Overridable via ENV for production tuning without a redeploy. The
  # Layer-1 hallucination firewall (deterministic fact gathering) applies
  # regardless of temperature.
  class RoundupClient < OpenAICompatibleClient
    Response = OpenAICompatibleClient::Response
    ConfigurationError = OpenAICompatibleClient::ConfigurationError
    RequestError = OpenAICompatibleClient::RequestError

    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_TEMPERATURE = 0.6
    REQUIRED_CONTENT_KEYS = %w[headline intro storyline].freeze

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_ROUNDUP_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_ROUNDUP_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      temperature: ENV.fetch("GENERATED_ROUNDUP_TEMPERATURE", DEFAULT_TEMPERATURE).to_f,
      max_input_chars: ENV.fetch("GENERATED_ROUNDUP_MAX_INPUT_CHARS", Generated::Prompts::MonthlyRoundupV1::DEFAULT_MAX_INPUT_CHARS).to_i,
      sleeper: nil
    )
      super(api_key:, api_base:, model_name:, timeout_seconds:, max_input_chars:, temperature:, sleeper:)
    end

    private

    def client_label
      "Roundup"
    end

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

    def normalize_strings(value)
      Array(value).map { |item| item.to_s.strip }.reject(&:blank?)
    end

    def normalize_blurbs(value)
      Array(value).filter_map do |entry|
        next unless entry.is_a?(Hash)

        matter_file = entry["matter_file"].to_s.strip
        blurb = entry["blurb"].to_s.strip
        next if matter_file.blank? || blurb.blank?

        { "matter_file" => matter_file, "blurb" => blurb }
      end
    end
  end
end
