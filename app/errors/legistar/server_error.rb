module Legistar
  # Raised when the Legistar API returns a 5xx status. Transient enough that
  # the caller should retry, not fail permanently.
  class ServerError < StandardError
    attr_reader :status_code, :request_url

    def initialize(status_code:, request_url:)
      @status_code = status_code
      @request_url = request_url
      super("Legistar API returned HTTP #{status_code} for #{request_url}")
    end
  end
end
