module Search
  # EmbeddingClient calls an OpenAI-compatible /embeddings endpoint and returns
  # a parsed Response. Uses the same provider-neutral pattern as
  # Generated::SummaryClient but targets the embeddings API rather than chat.
  class EmbeddingClient
    Response = Data.define(:vector, :model_name, :usage_metadata)

    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    DEFAULT_API_BASE = "https://api.openai.com/v1"
    DEFAULT_MODEL = "text-embedding-3-small"
    DEFAULT_DIMENSIONS = 1536
    DEFAULT_TIMEOUT_SECONDS = 30
    MAX_RETRIES = 3

    attr_reader :model_name, :dimensions

    def initialize(
      api_key: ENV["SEMANTIC_SEARCH_API_KEY"],
      api_base: ENV.fetch("SEMANTIC_SEARCH_API_BASE", DEFAULT_API_BASE),
      model_name: ENV.fetch("SEMANTIC_SEARCH_EMBEDDING_MODEL", DEFAULT_MODEL),
      dimensions: ENV.fetch("SEMANTIC_SEARCH_EMBEDDING_DIMENSIONS", DEFAULT_DIMENSIONS).to_i,
      timeout_seconds: ENV.fetch("SEMANTIC_SEARCH_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
      sleeper: nil
    )
      @api_key = api_key
      @api_base = api_base
      @model_name = model_name
      @dimensions = dimensions
      @timeout_seconds = timeout_seconds
      @sleeper = sleeper || method(:sleep)
    end

    def embed(input)
      raise ConfigurationError, "SEMANTIC_SEARCH_API_KEY is required" if @api_key.blank?

      response = post_embedding(input)
      vector = response.dig("data", 0, "embedding")
      raise RequestError, "Embedding response missing data[0].embedding" unless vector.is_a?(Array)

      Response.new(
        vector:,
        model_name: @model_name,
        usage_metadata: response.fetch("usage", {})
      )
    end

    private

    def post_embedding(input)
      uri = URI.join(@api_base.end_with?("/") ? @api_base : "#{@api_base}/", "embeddings")
      request_body = { model: @model_name, input: input }.to_json

      last_error = nil
      MAX_RETRIES.times do |attempt|
        @sleeper.call(backoff_seconds(attempt)) if attempt > 0

        begin
          response = perform_http_request(uri, request_body)
          status = response.code.to_i

          if status >= 400
            if retryable_response?(status)
              last_error = RequestError.new("Embedding request failed with status #{status}: #{error_message(response)}")
              next
            else
              raise RequestError, "Embedding request failed with status #{status}: #{error_message(response)}"
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
          raise RequestError, "Embedding endpoint returned invalid JSON: #{e.message}"
        end
      end

      raise RequestError, "Embedding request failed after #{MAX_RETRIES} attempts: #{last_error.message}"
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

    def error_message(response)
      body = JSON.parse(response.body) rescue nil
      body&.dig("error", "message").presence || response.message
    end

    def retryable_response?(status)
      status == 429 || status.between?(500, 599)
    end

    def backoff_seconds(attempt)
      2 ** attempt
    end
  end
end
