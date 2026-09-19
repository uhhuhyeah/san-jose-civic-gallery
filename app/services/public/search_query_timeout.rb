module Public
  class SearchQueryTimeout
    DEFAULT_TIMEOUT_MS = 5_000

    class Error < StandardError; end

    def self.call(timeout_ms: DEFAULT_TIMEOUT_MS, &)
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute(
          "SET LOCAL statement_timeout = #{ActiveRecord::Base.connection.quote("#{timeout_ms}ms")}"
        )
        yield
      end
    rescue ActiveRecord::QueryCanceled
      raise Error, "public search exceeded its database time budget"
    end
  end
end
