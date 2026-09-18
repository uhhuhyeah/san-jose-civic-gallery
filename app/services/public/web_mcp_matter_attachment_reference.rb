module Public
  # A signed handle issued only in a current public matter-detail response.
  # It binds an attachment to its matter and jurisdiction without exposing
  # database identifiers in the browser tool contract.
  class WebMcpMatterAttachmentReference
    PURPOSE = "webmcp-matter-attachment-reference/v1"

    def self.generate(attachment)
      verifier.generate(
        {
          "attachment_id" => attachment.id,
          "matter_id" => attachment.civic_matter_id,
          "jurisdiction_id" => attachment.civic_jurisdiction_id
        },
        purpose: PURPOSE
      )
    end

    def self.resolve(value, jurisdiction:)
      payload = verifier.verified(value.to_s, purpose: PURPOSE)
      return unless payload.is_a?(Hash)
      return unless payload["jurisdiction_id"] == jurisdiction.id

      Civic::MatterAttachment.current_from_source
        .for_jurisdiction(jurisdiction)
        .where(civic_matter_id: payload["matter_id"])
        .find_by(id: payload["attachment_id"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
