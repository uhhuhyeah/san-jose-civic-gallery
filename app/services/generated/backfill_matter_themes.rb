module Generated
  class BackfillMatterThemes
    DEFAULT_LIMIT = 10

    Result = Data.define(:dry_run, :candidates, :generated, :failed, :skipped)

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, client: ThemesClient.new, force: false)
      new(limit:, dry_run:, client:, force:).call
    end

    def initialize(limit:, dry_run:, client:, force:)
      @limit = limit.to_i
      @dry_run = dry_run
      @client = client
      @force = force
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

    attr_reader :limit, :dry_run, :client, :force

    def candidate_matters
      return [] unless limit.positive?
      return Civic::Matter.order(:id).limit(limit).to_a if force

      candidates = []
      Civic::Matter.order(:id).find_each do |matter|
        next if already_succeeded_for_current_input?(matter)

        candidates << matter
        break if candidates.size >= limit
      end
      candidates
    end

    def already_succeeded_for_current_input?(matter)
      Generated::Artifact.exists?(
        target: matter,
        kind: ClassifyMatterThemes::KIND,
        model_identifier: client_model_name,
        prompt_version: ClassifyMatterThemes::PROMPT::VERSION,
        input_sha256: ClassifyMatterThemes.current_input_sha256(matter:, client:),
        status: "succeeded"
      )
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : ThemesClient::DEFAULT_MODEL
    end
  end
end
