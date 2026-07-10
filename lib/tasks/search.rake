namespace :search do
  desc "Embed generated summaries for semantic search (dry run by default)"
  task :embed_summaries, %i[limit dry_run force] => :environment do |_task, args|
    limit = (args[:limit] || ENV["LIMIT"] || 10).to_i
    dry_run = parse_boolean(args[:dry_run] || ENV.fetch("DRY_RUN", "true"))
    force = parse_boolean(args[:force] || ENV.fetch("FORCE", "false"))

    result = Search::BackfillSummaryEmbeddings.call(limit:, dry_run:, force:)

    puts "Search::BackfillSummaryEmbeddings completed:"
    puts "  Dry run: #{result.dry_run}"
    puts "  Candidates: #{result.candidates.count}"
    puts "  Embedded: #{result.embedded}"
    puts "  Skipped: #{result.skipped}"
    puts "  Failed: #{result.failed}"

    if result.dry_run && result.candidates.any?
      puts ""
      puts "Candidate artifacts:"
      result.candidates.each do |artifact|
        puts "  - #{artifact.class.name} ##{artifact.id} (#{artifact.kind}) " \
             "target: #{artifact.target_type} ##{artifact.target_id}"
      end
    end
  end

  desc "Embed a specific artifact by ID: ARTIFACT_ID=123"
  task :embed_artifact, [ :artifact_id ] => :environment do |_task, args|
    artifact_id = args[:artifact_id] || ENV["ARTIFACT_ID"]
    abort "ARTIFACT_ID required" unless artifact_id

    artifact = Generated::Artifact.find(artifact_id)
    input = Search::BuildEmbeddingInput.call(artifact)
    content_sha256 = Digest::SHA256.hexdigest(input)

    puts "Artifact: #{artifact.class.name} ##{artifact.id} (#{artifact.kind})"
    puts "Input (#{input.length} chars):"
    puts input
    puts ""
    puts "Content SHA256: #{content_sha256}"
  end

  def parse_boolean(value)
    %w[true 1 yes].include?(value.to_s.downcase)
  end
end
