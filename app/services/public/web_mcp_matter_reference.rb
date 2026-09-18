module Public
  # A signed, opaque handle for a public matter returned by WebMCP search.
  # It avoids making database IDs part of the browser-facing tool contract and
  # binds the handle to one jurisdiction.
  class WebMcpMatterReference
    PURPOSE = "webmcp-matter-reference/v1"

    def self.generate(matter)
      verifier.generate(
        { "matter_id" => matter.id, "jurisdiction_id" => matter.civic_jurisdiction_id },
        purpose: PURPOSE
      )
    end

    def self.resolve(value, jurisdiction:)
      payload = verifier.verified(value.to_s, purpose: PURPOSE)
      return unless payload.is_a?(Hash)
      return unless payload["jurisdiction_id"] == jurisdiction.id

      Civic::Matter.for_jurisdiction(jurisdiction).find_by(id: payload["matter_id"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
