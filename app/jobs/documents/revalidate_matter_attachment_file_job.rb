module Documents
  class RevalidateMatterAttachmentFileJob < ApplicationJob
    queue_as :default

    def perform(civic_matter_attachment_id)
      matter_attachment = Civic::MatterAttachment.find(civic_matter_attachment_id)
      result = RevalidateMatterAttachmentFile.call(matter_attachment:)
      Rails.logger.info(
        "Documents::RevalidateMatterAttachmentFileJob #{result.action} " \
        "matter attachment #{matter_attachment.legistar_matter_attachment_id}"
      )
      result
    end
  end
end
