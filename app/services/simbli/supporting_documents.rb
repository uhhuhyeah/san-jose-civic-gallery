module Simbli
  # Parses Simbli's GetSupportingDocuments response into attachment metadata.
  # Identity is the numeric AttachmentID; the encrypted EncrId is ignored.
  class SupportingDocuments
    Attachment = Data.define(:attachment_id, :title, :file_name, :content_type, :file_extension, :order)

    def self.parse(payload)
      list = payload.is_a?(Hash) ? payload["Attachment"] : payload
      Array(list).map do |doc|
        Attachment.new(
          attachment_id: doc["AttachmentID"],
          title: doc["Title"].to_s.strip,
          file_name: doc["FileName"],
          content_type: doc["ContentType"],
          file_extension: doc["FileExtension"],
          order: doc["Order"]
        )
      end
    end
  end
end
