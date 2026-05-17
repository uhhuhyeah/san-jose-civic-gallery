namespace :documents do
  desc "Backfill imported attachment files and extracted/OCR text. Set RUN=true to enqueue jobs."
  task backfill: :environment do
    result = Documents::BackfillMatterAttachments.call(
      limit: ENV.fetch("LIMIT", Documents::BackfillMatterAttachments::DEFAULT_LIMIT),
      dry_run: ENV.fetch("RUN", "false") != "true",
      matter_file: ENV["MATTER_FILE"],
      from_date: ENV["FROM_DATE"],
      to_date: ENV["TO_DATE"],
      retry_errors: ENV["RETRY_ERRORS"] == "true"
    )

    mode = result.dry_run ? "dry-run" : "enqueue"
    puts "Document backfill #{mode}"
    puts "Import candidates: #{result.import_candidates.size}"
    puts "Extraction candidates: #{result.extraction_candidates.size}"
    puts "Import jobs enqueued: #{result.import_enqueued}"
    puts "Extraction jobs enqueued: #{result.extraction_enqueued}"

    if result.import_candidates.any?
      puts
      puts "Import attachment IDs:"
      result.import_candidates.each { |attachment| puts "- #{attachment.id} #{attachment.matter.matter_file} #{attachment.name}" }
    end

    if result.extraction_candidates.any?
      puts
      puts "Extraction attachment IDs:"
      result.extraction_candidates.each { |attachment| puts "- #{attachment.id} #{attachment.matter.matter_file} #{attachment.name}" }
    end
  end
end
