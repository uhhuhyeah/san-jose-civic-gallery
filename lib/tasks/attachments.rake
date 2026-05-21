require "csv"

namespace :attachments do
  CSV_BEGIN_SENTINEL = "===NEEDS_MANUAL_UPLOAD_CSV_BEGIN===".freeze
  CSV_END_SENTINEL = "===NEEDS_MANUAL_UPLOAD_CSV_END===".freeze
  CSV_HEADERS = %w[
    attachment_id
    jurisdiction
    source_system
    matter_file
    attachment_name
    error_status
    error_message
    hyperlink
    pdf_path
    reason
  ].freeze

  desc "Emit a CSV of Civic::MatterAttachment rows that need a manually uploaded " \
       "file. Default: rows that failed the automated import (honors STATUS to " \
       "filter by error_status, e.g. STATUS=403). With JURISDICTION=<slug> " \
       "(e.g. sjusd): rows lacking a stored file for that jurisdiction, whose " \
       "downloads are blocked at the source (no STATUS filter). Narrow by meeting " \
       "date with YEAR=2026 or FROM_DATE/TO_DATE=YYYY-MM-DD."
  task needs_manual_upload: :environment do
    jurisdiction_slug = ENV["JURISDICTION"].to_s.strip.presence
    status_filter = ENV["STATUS"].to_s.strip.presence

    from_date = to_date = nil
    begin
      if (year = ENV["YEAR"].to_s.strip.presence)
        from_date = Date.new(Integer(year), 1, 1)
        to_date = Date.new(Integer(year), 12, 31)
      else
        from_date = ENV["FROM_DATE"].to_s.strip.presence&.then { |d| Date.iso8601(d) }
        to_date = ENV["TO_DATE"].to_s.strip.presence&.then { |d| Date.iso8601(d) }
      end
    rescue ArgumentError, TypeError => error
      abort "Invalid date filter (use YEAR=2026 or FROM_DATE/TO_DATE=YYYY-MM-DD): #{error.message}"
    end

    if jurisdiction_slug
      jurisdiction = Civic::Jurisdiction.find_by!(slug: jurisdiction_slug)
      candidates = Civic::MatterAttachment.for_jurisdiction(jurisdiction).awaiting_file
      status_filter = nil # no recorded errors on these; STATUS does not apply
    else
      candidates = Civic::MatterAttachment.needs_manual_upload
    end

    # Narrow by the meeting (event) date. SJUSD synthetic matters carry no
    # agenda_date, so the only reliable date is the event their agenda item
    # belongs to: attachment -> matter -> event_items -> event.
    if from_date || to_date
      date_range =
        if from_date && to_date then from_date..to_date
        elsif from_date then from_date..
        else ..to_date
        end
      candidates = candidates
        .joins(matter: { event_items: :event })
        .where(civic_events: { event_date: date_range })
        .distinct
    end

    candidates = candidates.includes(:matter, :civic_jurisdiction).order(:created_at)

    rows = candidates.map do |attachment|
      error_text = attachment.source_file_import_error.to_s
      {
        attachment_id: attachment.id,
        jurisdiction: attachment.civic_jurisdiction&.slug,
        source_system: attachment.source_system,
        matter_file: attachment.matter&.matter_file,
        attachment_name: attachment.name,
        hyperlink: attachment.hyperlink,
        error_status: error_text[/HTTP (\d+)/, 1] || (error_text.present? ? "ERR" : ""),
        error_message: error_text.lines.first.to_s.strip
      }
    end

    total = rows.size
    rows = rows.select { |row| row[:error_status] == status_filter } if status_filter
    filtered_out = total - rows.size

    csv_body = CSV.generate do |csv|
      csv << CSV_HEADERS
      rows.each do |row|
        csv << [
          row[:attachment_id],
          row[:jurisdiction],
          row[:source_system],
          row[:matter_file],
          row[:attachment_name],
          row[:error_status],
          row[:error_message],
          row[:hyperlink],
          nil,
          nil
        ]
      end
    end

    puts CSV_BEGIN_SENTINEL
    print csv_body
    puts CSV_END_SENTINEL

    summary = "needs_manual_upload: #{rows.size} rows"
    summary += " for jurisdiction=#{jurisdiction_slug}" if jurisdiction_slug
    summary += " (meeting date #{from_date}..#{to_date})" if from_date || to_date
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
