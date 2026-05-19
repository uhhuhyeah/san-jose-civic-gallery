module Ingestion
  module Coerce
    class InvalidPayload < StandardError; end

    module_function

    def date(value, field:)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError => error
      raise InvalidPayload, "Invalid date for #{field}: #{value.inspect} (#{error.message})"
    end

    def datetime(value, field:)
      return nil if value.blank?

      Time.zone.parse(value.to_s) ||
        raise(InvalidPayload, "Invalid datetime for #{field}: #{value.inspect}")
    rescue ArgumentError, TypeError => error
      raise InvalidPayload, "Invalid datetime for #{field}: #{value.inspect} (#{error.message})"
    end
  end
end
