namespace :generated do
  desc "Classify matters into themes. Set RUN=true to call the configured model. " \
    "Options: LIMIT (integer, default 10), FORCE=true to re-classify already-tagged matters."
  task classify_matter_themes: :environment do
    limit = if ENV["LIMIT"].present?
      parsed_limit = Integer(ENV["LIMIT"], exception: false)
      unless parsed_limit && parsed_limit.positive?
        abort "LIMIT must be a positive integer (got #{ENV['LIMIT'].inspect})"
      end
      parsed_limit
    else
      Generated::BackfillMatterThemes::DEFAULT_LIMIT
    end

    client = Generated::ThemesClient.new
    result = Generated::BackfillMatterThemes.call(
      limit:,
      dry_run: ENV.fetch("RUN", "false") != "true",
      force: ENV["FORCE"] == "true",
      client:
    )

    mode = result.dry_run ? "dry-run" : "classify"
    puts "Matter theme #{mode}"
    puts "Model: #{client.model_name}"
    puts "Prompt: #{Generated::ClassifyMatterThemes::PROMPT::VERSION}"
    puts "Candidates: #{result.candidates.size}"
    puts "Generated: #{result.generated}"
    puts "Failed: #{result.failed}"
    puts "Skipped: #{result.skipped}"

    if result.candidates.any?
      puts
      puts "Candidate matter IDs:"
      result.candidates.each { |matter| puts "- #{matter.id} #{matter.matter_file} #{matter.descriptive_title}" }
    end
  end
end

namespace :pulse do
  desc "Preview tagged theme data before the aggregation UI exists. " \
    "Options: WEEKS (integer, window agenda appearances to the last N weeks; default all-time), " \
    "SAMPLES (integer, sample matters printed per theme; default 3)."
  task preview: :environment do
    weeks = Integer(ENV["WEEKS"], exception: false) if ENV["WEEKS"].present?
    samples = Integer(ENV["SAMPLES"], exception: false) || 3
    since = weeks ? weeks.weeks.ago.to_date : nil

    total_matters = Civic::Matter.count
    tagged_matters = Civic::MatterTheme.distinct.count(:civic_matter_id)
    coverage = total_matters.zero? ? 0 : (tagged_matters.to_f / total_matters * 100).round(1)

    puts "Theme tagging preview"
    puts "Window: #{since ? "agenda appearances since #{since}" : "all-time"}"
    puts "Matters tagged: #{tagged_matters} / #{total_matters} (#{coverage}%)"
    puts

    rows = Civic::ThemeTaxonomy::THEMES.map do |theme|
      matter_ids = Civic::MatterTheme.for_theme(theme[:slug]).select(:civic_matter_id)
      events = Civic::EventItem.where(civic_matter_id: matter_ids).joins(:event)
      events = events.where(civic_events: { event_date: since.. }) if since

      { label: theme[:label], slug: theme[:slug], matters: matter_ids.count, appearances: events.count }
    end

    rows.sort_by! { |row| -row[:appearances] }

    label_width = rows.map { |row| row[:label].length }.max || 0
    puts format("%-#{label_width}s  %8s  %12s", "Theme", "Matters", "Appearances")
    rows.each do |row|
      puts format("%-#{label_width}s  %8d  %12d", row[:label], row[:matters], row[:appearances])
    end

    next if samples.zero?

    puts
    puts "Sample matters per theme (most recent #{samples}):"
    rows.each do |row|
      next if row[:matters].zero?

      matter_ids = Civic::MatterTheme.for_theme(row[:slug]).select(:civic_matter_id)
      sample = Civic::Matter.where(id: matter_ids).recent_first.limit(samples)
      puts
      puts "#{row[:label]} (#{row[:matters]} matters):"
      sample.each { |matter| puts "  - #{matter.matter_file} #{matter.descriptive_title}" }
    end
  end
end
