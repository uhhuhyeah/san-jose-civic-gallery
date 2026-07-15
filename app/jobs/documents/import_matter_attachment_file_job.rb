module Documents
  class ImportMatterAttachmentFileJob < ApplicationJob
    queue_as :default

    discard_on Documents::SafeHttpClient::TooLargeError

    def perform(civic_matter_attachment_id)
      matter_attachment = Civic::MatterAttachment.find(civic_matter_attachment_id)
      matter_attachment = ImportMatterAttachmentFile.call(matter_attachment:)
      ExtractMatterAttachmentTextJob.perform_later(matter_attachment.id) if matter_attachment.extractable_as_pdf?
      Rails.logger.info("Documents::ImportMatterAttachmentFileJob imported file for matter attachment #{matter_attachment.legistar_matter_attachment_id}")
    end
  end
end
