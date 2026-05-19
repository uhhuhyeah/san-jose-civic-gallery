namespace :attachments do
  desc "Manually attach a PDF to a Civic::MatterAttachment when the source URL " \
       "is not retrievable by the automated importer. " \
       "Required env vars: ATTACHMENT_ID, PDF_PATH, OPERATOR, REASON."
  task manual_upload: :environment do
    attachment_id = Integer(ENV.fetch("ATTACHMENT_ID"))
    pdf_path      = ENV.fetch("PDF_PATH")
    operator      = ENV.fetch("OPERATOR")
    reason        = ENV.fetch("REASON")

    attachment = Documents::ManualUploadAttachment.call(
      attachment_id: attachment_id,
      pdf_path: pdf_path,
      operator: operator,
      reason: reason
    )

    puts "Manually attached PDF to Civic::MatterAttachment ##{attachment.id}"
    puts "  matter file:    #{attachment.matter.matter_file}"
    puts "  filename:       #{attachment.source_file.filename}"
    puts "  bytes:          #{attachment.source_file_byte_size}"
    puts "  checksum:       #{attachment.source_file_checksum_sha256[0, 12]}..."
    puts "  uploaded by:    #{attachment.manually_imported_by}"
    puts "  reason:         #{attachment.manual_import_reason}"
    puts "  extraction job has been enqueued."
  end
end
