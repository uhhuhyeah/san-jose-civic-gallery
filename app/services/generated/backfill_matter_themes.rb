module Generated
  class BackfillMatterThemes
    DEFAULT_LIMIT = 10

    Result = Data.define(:dry_run, :candidates, :generated, :failed, :skipped)

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, client: ThemesClient.new, force: false, jurisdiction: nil)
      new(limit:, dry_run:, client:, force:, jurisdiction:).call
    end

    def initialize(limit:, dry_run:, client:, force:, jurisdiction: nil)
      @limit = limit.to_i
      @dry_run = dry_run
      @client = client
      @force = force
      @jurisdiction = jurisdiction
    end

    def call
      candidates = candidate_matters
      generated = 0
      failed = 0
      skipped = 0

      unless dry_run
        candidates.each do |matter|
          result = ClassifyMatterThemes.call(matter:, client:, force:)
          if result.artifact.status == "succeeded"
            result.skipped ? skipped += 1 : generated += 1
          else
            failed += 1
          end
        end
      end

      Result.new(dry_run:, candidates:, generated:, failed:, skipped:)
    end

    private

    attr_reader :limit, :dry_run, :client, :force, :jurisdiction

    def candidate_matters
      return [] unless limit.positive?
      return recency_first.limit(limit).to_a if force

      candidates = []
      recency_first.each do |matter|
        next if already_succeeded_for_current_input?(matter)

        candidates << matter
        break if candidates.size >= limit
      end
      candidates
    end

    # Newest-agendized matters first so re-tags (after a prompt change) and
    # validation converge on the matters the pulse actually measures, instead
    # of finishing with them. Never-agendized matters (null agenda_date) are
    # least pulse-relevant, so they sort last. `id DESC` is a stable final
    # tiebreaker (e.g. for SJUSD synthetic matters whose date/legistar columns
    # are all null). Scoped to a single jurisdiction when one is given.
    def recency_first
      scope = jurisdiction ? Civic::Matter.for_jurisdiction(jurisdiction) : Civic::Matter.all
      scope.order(
        Arel.sql("agenda_date DESC NULLS LAST, intro_date DESC NULLS LAST, legistar_matter_id DESC NULLS LAST, id DESC")
      )
    end

    def already_succeeded_for_current_input?(matter)
      Generated::Artifact.exists?(
        target: matter,
        kind: ClassifyMatterThemes::KIND,
        model_identifier: client_model_name,
        prompt_version: ClassifyMatterThemes.prompt_for(matter)::VERSION,
        input_sha256: ClassifyMatterThemes.current_input_sha256(matter:, client:),
        status: "succeeded"
      )
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : ThemesClient::DEFAULT_MODEL
    end
  end
end
