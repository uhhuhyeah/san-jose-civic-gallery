namespace :attachments do
  desc "List Civic::MatterAttachment rows that failed the automated import " \
       "and have not yet been manually uploaded, grouped by source host."
  task needs_manual_upload: :environment do
    candidates = Civic::MatterAttachment
      .needs_manual_upload
      .includes(:matter)
      .order(:created_at)

    total = candidates.size
    if total.zero?
      puts "No attachments are currently waiting on manual upload."
      next
    end

    hosts = candidates.group_by do |attachment|
      begin
        URI.parse(attachment.hyperlink.to_s).host || "(unparseable)"
      rescue URI::InvalidURIError
        "(invalid)"
      end
    end

    noun = total == 1 ? "attachment" : "attachments"
    verb = total == 1 ? "needs" : "need"
    puts "#{total} #{noun} #{verb} manual upload (grouped by host):"
    hosts.sort_by { |host, rows| -rows.size }.each do |host, rows|
      puts "  #{host.ljust(28)} #{rows.size}"
    end
    puts

    candidates.each do |attachment|
      matter_file = attachment.matter&.matter_file || "(no matter)"
      error_summary = attachment.source_file_import_error.to_s.lines.first.to_s.strip[0, 200]

      puts "[id=#{attachment.id}] #{matter_file}  #{attachment.name}"
      puts "       #{attachment.hyperlink}"
      puts "       #{error_summary}"
      puts
    end
  end

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
