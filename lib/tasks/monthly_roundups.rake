namespace :generated do
  desc "Generate monthly roundups per jurisdiction. Set RUN=true to " \
    "call the configured model. Options: LIMIT (integer, default 1), " \
    "FORCE=true to regenerate frozen periods, JURISDICTION=<slug> to " \
    "scope to one jurisdiction (default: all), MONTH=YYYY-MM to target " \
    "one specific month."
  task generate_roundups: :environment do
    limit = if ENV["LIMIT"].present?
      parsed_limit = Integer(ENV["LIMIT"], exception: false)
      unless parsed_limit && parsed_limit.positive?
        abort "LIMIT must be a positive integer (got #{ENV['LIMIT'].inspect})"
      end
      parsed_limit
    else
      Generated::BackfillMonthlyRoundups::DEFAULT_LIMIT
    end

    jurisdiction_slug = ENV["JURISDICTION"].to_s.strip.presence
    jurisdiction = Civic::Jurisdiction.find_by!(slug: jurisdiction_slug) if jurisdiction_slug

    target_month = if ENV["MONTH"].present?
      Date.parse("#{ENV['MONTH']}-01")
    else
      nil
    end

    client = Generated::RoundupClient.new
    result = Generated::BackfillMonthlyRoundups.call(
      limit:,
      dry_run: ENV.fetch("RUN", "false") != "true",
      force: ENV["FORCE"] == "true",
      client:,
      jurisdiction:,
      month: target_month
    )

    mode = result.dry_run ? "dry-run" : "generate"
    puts "Monthly roundup #{mode}"
    puts "Model: #{client.model_name}"
    puts "Prompt version: #{Generated::SummarizeRoundup::PROMPT::VERSION}"
    puts "Jurisdiction: #{jurisdiction_slug || 'all'}"
    puts "Candidates: #{result.candidates.size}"
    puts "Generated: #{result.generated}"
    puts "Failed: #{result.failed}"
    puts "Skipped: #{result.skipped}"

    if result.candidates.any?
      puts
      puts "Candidate periods:"
      result.candidates.each { |period| puts "- #{period.label}" }
    end
  end
end
