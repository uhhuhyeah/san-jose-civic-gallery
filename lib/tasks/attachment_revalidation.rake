namespace :documents do
  desc "Revalidate imported attachment files. Set RUN=true to enqueue jobs."
  task revalidate_attachments: :environment do
    revalidate_after = if ENV["REVALIDATE_AFTER_DAYS"].present?
      raw = ENV["REVALIDATE_AFTER_DAYS"]
      days = Integer(raw, exception: false)
      unless days && days >= 0
        abort "REVALIDATE_AFTER_DAYS must be a non-negative integer (got #{raw.inspect})"
      end
      days.days
    else
      Documents::BackfillAttachmentRevalidations::DEFAULT_REVALIDATE_AFTER
    end

    result = Documents::BackfillAttachmentRevalidations.call(
      limit: ENV.fetch("LIMIT", Documents::BackfillAttachmentRevalidations::DEFAULT_LIMIT),
      dry_run: ENV.fetch("RUN", "false") != "true",
      revalidate_after:,
      retry_errors: ENV["RETRY_ERRORS"] == "true"
    )

    mode = result.dry_run ? "dry-run" : "enqueue"
    puts "Attachment revalidation #{mode}"
    puts "Candidates: #{result.candidates.size}"
    puts "Jobs enqueued: #{result.enqueued}"

    if result.candidates.any?
      puts
      puts "Attachment IDs:"
      result.candidates.each do |attachment|
        puts "- #{attachment.id} #{attachment.matter.matter_file} #{attachment.name}"
      end
    end
  end
end
