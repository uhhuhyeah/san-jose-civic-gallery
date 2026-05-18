namespace :documents do
  desc "Revalidate imported attachment files. Set RUN=true to enqueue jobs."
  task revalidate_attachments: :environment do
    revalidate_after = if ENV["REVALIDATE_AFTER_DAYS"].present?
      ENV["REVALIDATE_AFTER_DAYS"].to_i.days
    else
      Documents::BackfillAttachmentRevalidations::DEFAULT_REVALIDATE_AFTER
    end

    result = Documents::BackfillAttachmentRevalidations.call(
      limit: ENV.fetch("LIMIT", Documents::BackfillAttachmentRevalidations::DEFAULT_LIMIT),
      dry_run: ENV.fetch("RUN", "false") != "true",
      revalidate_after:
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
