namespace :generated do
  desc "Classify matters into themes. Set RUN=true to call the configured model. " \
    "Options: LIMIT (integer, default 10), FORCE=true to re-classify already-tagged " \
    "matters, JURISDICTION=<slug> (e.g. sjusd) to scope to one jurisdiction (default: all)."
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

    jurisdiction_slug = ENV["JURISDICTION"].to_s.strip.presence
    jurisdiction = Civic::Jurisdiction.find_by!(slug: jurisdiction_slug) if jurisdiction_slug

    client = Generated::ThemesClient.new
    result = Generated::BackfillMatterThemes.call(
      limit:,
      dry_run: ENV.fetch("RUN", "false") != "true",
      force: ENV["FORCE"] == "true",
      client:,
      jurisdiction:
    )

    mode = result.dry_run ? "dry-run" : "classify"
    puts "Matter theme #{mode}"
    puts "Model: #{client.model_name}"
    puts "Jurisdiction: #{jurisdiction_slug || 'all'}"
    if jurisdiction
      prompt = Generated::ClassifyMatterThemes::PROMPTS_BY_JURISDICTION
        .fetch(jurisdiction.slug, Generated::ClassifyMatterThemes::DEFAULT_PROMPT)
      puts "Prompt: #{prompt::VERSION}"
    else
      puts "Prompt: resolved per matter jurisdiction"
    end
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
    "Options: JURISDICTION=<slug> (default sanjose), " \
    "WEEKS (integer, window agenda appearances to the last N weeks; default all-time), " \
    "SAMPLES (integer, sample matters printed per theme; default 3)."
  task preview: :environment do
    jurisdiction = Civic::Jurisdiction.find_by!(slug: ENV.fetch("JURISDICTION", "sanjose"))
    weeks = Integer(ENV["WEEKS"], exception: false) if ENV["WEEKS"].present?
    samples = Integer(ENV["SAMPLES"], exception: false) || 3
    since = weeks ? weeks.weeks.ago.to_date : nil

    matters = Civic::Matter.for_jurisdiction(jurisdiction)
    tagged_in_jurisdiction = Civic::MatterTheme.joins(:matter).merge(matters)

    total_matters = matters.count
    tagged_matters = tagged_in_jurisdiction.distinct.count(:civic_matter_id)
    coverage = total_matters.zero? ? 0 : (tagged_matters.to_f / total_matters * 100).round(1)

    puts "Theme tagging preview"
    puts "Jurisdiction: #{jurisdiction.slug}"
    puts "Window: #{since ? "agenda appearances since #{since}" : "all-time"}"
    puts "Matters tagged: #{tagged_matters} / #{total_matters} (#{coverage}%)"
    puts

    rows = Civic::ThemeTaxonomy.themes_for(jurisdiction).map do |theme|
      matter_ids = tagged_in_jurisdiction.where(civic_matter_themes: { theme_slug: theme[:slug] }).select(:civic_matter_id)
      primary_ids = tagged_in_jurisdiction.merge(Civic::MatterTheme.primary)
        .where(civic_matter_themes: { theme_slug: theme[:slug] }).select(:civic_matter_id)
      events = Civic::EventItem.current_from_source
        .where(civic_matter_id: primary_ids)
        .joins(:event)
        .merge(Civic::Event.current_from_source.for_jurisdiction(jurisdiction))
      events = events.where(civic_events: { event_date: since.. }) if since

      {
        label: theme[:label],
        slug: theme[:slug],
        matters: matter_ids.count,
        primary: primary_ids.count,
        appearances: events.count
      }
    end

    rows.sort_by! { |row| -row[:appearances] }

    label_width = rows.map { |row| row[:label].length }.max || 0
    puts format("%-#{label_width}s  %8s  %8s  %14s", "Theme", "Matters", "Primary", "Appearances*")
    rows.each do |row|
      puts format("%-#{label_width}s  %8d  %8d  %14d", row[:label], row[:matters], row[:primary], row[:appearances])
    end
    puts "* Appearances count matters where this is the primary (rank 1) theme."

    next if samples.zero?

    puts
    puts "Sample matters per theme (most recent #{samples}):"
    rows.each do |row|
      next if row[:matters].zero?

      sample = matters.where(id: tagged_in_jurisdiction.where(civic_matter_themes: { theme_slug: row[:slug] }).select(:civic_matter_id))
        .recent_first.limit(samples)
      puts
      puts "#{row[:label]} (#{row[:matters]} matters):"
      sample.each { |matter| puts "  - #{matter.matter_file} #{matter.descriptive_title}" }
    end
  end
end
