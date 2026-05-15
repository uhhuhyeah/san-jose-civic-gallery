module Documents
  class ImportMatterAttachmentFileJob < ApplicationJob
    queue_as :default

    def perform(civic_matter_attachment_id)
      matter_attachment = Civic::MatterAttachment.find(civic_matter_attachment_id)
      ImportMatterAttachmentFile.call(matter_attachment:)
      Rails.logger.info("Documents::ImportMatterAttachmentFileJob imported file for matter attachment #{matter_attachment.legistar_matter_attachment_id}")
    end
  end
end
