namespace :generated do
  desc "Generate attachment summaries from extracted text. Set RUN=true to call the configured model."
  task summarize_attachments: :environment do
    result = Generated::BackfillAttachmentSummaries.call(
      limit: ENV.fetch("LIMIT", Generated::BackfillAttachmentSummaries::DEFAULT_LIMIT),
      dry_run: ENV.fetch("RUN", "false") != "true",
      force: ENV["FORCE"] == "true"
    )

    mode = result.dry_run ? "dry-run" : "generate"
    puts "Attachment summary #{mode}"
    puts "Candidates: #{result.candidates.size}"
    puts "Generated: #{result.generated}"
    puts "Failed: #{result.failed}"
    puts "Skipped: #{result.skipped}"

    if result.candidates.any?
      puts
      puts "Candidate attachment IDs:"
      result.candidates.each { |attachment| puts "- #{attachment.id} #{attachment.matter.matter_file} #{attachment.name}" }
    end
  end
end
