module Ingestion
  module FanOut
    module_function

    def dispatch(mode:, inline: nil, deferred: nil)
      case normalize_mode(mode)
      when :off
        nil
      when :inline
        inline&.call
      when :deferred
        deferred&.call
      end
    end

    def normalize_mode(mode)
      return :inline if mode == true
      return :off if mode == false

      mode
    end
  end
end
