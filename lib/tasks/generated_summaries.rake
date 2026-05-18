namespace :generated do
  desc "Generate attachment summaries from extracted text. Set RUN=true to call the configured model. " \
    "Options: LIMIT (integer, default 10), FORCE=true to re-generate already-summarized attachments."
  task summarize_attachments: :environment do
    limit = if ENV["LIMIT"].present?
      parsed_limit = Integer(ENV["LIMIT"], exception: false)
      unless parsed_limit && parsed_limit.positive?
        abort "LIMIT must be a positive integer (got #{ENV['LIMIT'].inspect})"
      end
      parsed_limit
    else
      Generated::BackfillAttachmentSummaries::DEFAULT_LIMIT
    end

    client = Generated::SummaryClient.new
    result = Generated::BackfillAttachmentSummaries.call(
      limit:,
      dry_run: ENV.fetch("RUN", "false") != "true",
      force: ENV["FORCE"] == "true",
      client:
    )

    mode = result.dry_run ? "dry-run" : "generate"
    puts "Attachment summary #{mode}"
    puts "Model: #{client.model_name}"
    puts "Prompt: #{Generated::SummarizeMatterAttachment::PROMPT::VERSION}"
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
