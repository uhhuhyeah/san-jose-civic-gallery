require "csv"

namespace :attachments do
  CSV_BEGIN_SENTINEL = "===NEEDS_MANUAL_UPLOAD_CSV_BEGIN===".freeze
  CSV_END_SENTINEL = "===NEEDS_MANUAL_UPLOAD_CSV_END===".freeze
  CSV_HEADERS = %w[
    attachment_id
    matter_file
    attachment_name
    hyperlink
    error_status
    error_message
    pdf_path
    reason
  ].freeze

  desc "Emit a CSV of Civic::MatterAttachment rows that failed the automated " \
       "import and have not yet been manually uploaded. Honors STATUS env var " \
       "to filter by error_status (e.g. STATUS=403, STATUS=ERR)."
  task needs_manual_upload: :environment do
    status_filter = ENV["STATUS"].to_s.strip
    status_filter = nil if status_filter.empty?

    candidates = Civic::MatterAttachment
      .needs_manual_upload
      .includes(:matter)
      .order(:created_at)

    rows = candidates.map do |attachment|
      error_text = attachment.source_file_import_error.to_s
      error_status = error_text[/HTTP (\d+)/, 1] || "ERR"
      error_message = error_text.lines.first.to_s.strip

      {
        attachment_id: attachment.id,
        matter_file: attachment.matter&.matter_file,
        attachment_name: attachment.name,
        hyperlink: attachment.hyperlink,
        error_status: error_status,
        error_message: error_message
      }
    end

    total = rows.size
    if status_filter
      rows = rows.select { |row| row[:error_status] == status_filter }
    end
    filtered_out = total - rows.size

    csv_body = CSV.generate do |csv|
      csv << CSV_HEADERS
      rows.each do |row|
        csv << [
          row[:attachment_id],
          row[:matter_file],
          row[:attachment_name],
          row[:hyperlink],
          row[:error_status],
          row[:error_message],
          nil,
          nil
        ]
      end
    end

    puts CSV_BEGIN_SENTINEL
    print csv_body
    puts CSV_END_SENTINEL

    summary = "needs_manual_upload: #{rows.size} rows"
    summary += " (#{filtered_out} filtered out by STATUS=#{status_filter})" if status_filter
    warn summary
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
