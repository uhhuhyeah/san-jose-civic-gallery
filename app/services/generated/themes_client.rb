module Generated
  # ThemesClient calls an OpenAI-compatible /chat/completions endpoint and
  # returns the matter themes selected by the model. It honors the same
  # duck-typed contract as SummaryClient (call/model_name/max_input_chars)
  # so the classification service can accept a fake in tests.
  #
  # Provider credentials are shared with the other generated clients; only
  # the model and limits are themes-specific. The taxonomy is per-jurisdiction
  # and the client does not know the matter, so filtering returned slugs
  # against the vocabulary is the caller's job.
  class ThemesClient < OpenAICompatibleClient
    Response = OpenAICompatibleClient::Response
    ConfigurationError = OpenAICompatibleClient::ConfigurationError
    RequestError = OpenAICompatibleClient::RequestError

    DEFAULT_MODEL = "gpt-4o-mini"

    def initialize(
      api_key: ENV["GENERATED_SUMMARY_API_KEY"],
      api_base: ENV.fetch("GENERATED_SUMMARY_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("GENERATED_THEMES_MODEL", DEFAULT_MODEL),
      timeout_seconds: ENV.fetch("GENERATED_THEMES_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      max_input_chars: ENV.fetch("GENERATED_THEMES_MAX_INPUT_CHARS", Generated::Prompts::MatterThemesBase::DEFAULT_MAX_INPUT_CHARS).to_i,
      temperature: 0.0,
      sleeper: nil
    )
      super(api_key:, api_base:, model_name:, timeout_seconds:, max_input_chars:, temperature:, sleeper:)
    end

    private

    def client_label
      "Themes"
    end

    def normalize_content_shape(parsed_content)
      unless parsed_content.is_a?(Hash) && parsed_content.key?("themes")
        raise RequestError, "Themes model response must be an object with a \"themes\" array"
      end

      { "themes" => Array(parsed_content["themes"]).flatten.map(&:to_s) }
    end
  end
end
