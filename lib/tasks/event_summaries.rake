namespace :generated do
  desc "Summarize meetings (events) once minutes are published. Set RUN=true to " \
    "call the configured model. Options: LIMIT (integer, default 10), FORCE=true " \
    "to re-summarize events already done, JURISDICTION=<slug> (e.g. sjusd) to " \
    "scope to one jurisdiction (default: all)."
  task summarize_events: :environment do
    limit = if ENV["LIMIT"].present?
      parsed_limit = Integer(ENV["LIMIT"], exception: false)
      unless parsed_limit && parsed_limit.positive?
        abort "LIMIT must be a positive integer (got #{ENV['LIMIT'].inspect})"
      end
      parsed_limit
    else
      Generated::BackfillEventSummaries::DEFAULT_LIMIT
    end

    jurisdiction_slug = ENV["JURISDICTION"].to_s.strip.presence
    jurisdiction = Civic::Jurisdiction.find_by!(slug: jurisdiction_slug) if jurisdiction_slug

    client = Generated::EventSummaryClient.new
    result = Generated::BackfillEventSummaries.call(
      limit:,
      dry_run: ENV.fetch("RUN", "false") != "true",
      force: ENV["FORCE"] == "true",
      client:,
      jurisdiction:
    )

    mode = result.dry_run ? "dry-run" : "summarize"
    puts "Event summary #{mode}"
    puts "Model: #{client.model_name}"
    puts "Prompt: #{Generated::SummarizeEvent::PROMPT::VERSION}"
    puts "Jurisdiction: #{jurisdiction_slug || 'all'}"
    puts "Candidates: #{result.candidates.size}"
    puts "Generated: #{result.generated}"
    puts "Failed: #{result.failed}"
    puts "Skipped: #{result.skipped}"

    if result.candidates.any?
      puts
      puts "Candidate event IDs:"
      result.candidates.each { |event| puts "- #{event.id} #{event.event_date} #{event.display_name}" }
    end
  end
end
