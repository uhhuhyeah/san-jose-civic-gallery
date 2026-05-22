module Generated
  # Batch orchestrator for event summaries. Candidates are events that have a
  # published agenda (at least one current item), newest first, that do not
  # already have a successful event_summary artifact for the current model +
  # prompt version + input hash. Safe to run on a recurring basis: unchanged
  # events are skipped, and an event whose item set changed is re-summarized
  # because its input hash changes.
  class BackfillEventSummaries
    DEFAULT_LIMIT = 10

    Result = Data.define(:dry_run, :candidates, :generated, :failed, :skipped)

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, client: EventSummaryClient.new, force: false, jurisdiction: nil)
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
      candidates = candidate_events
      generated = 0
      failed = 0
      skipped = 0

      unless dry_run
        candidates.each do |event|
          result = SummarizeEvent.call(event:, client:, force:)
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

    def candidate_events
      return [] unless limit.positive?
      return recency_first.limit(limit).to_a if force

      candidates = []
      recency_first.each do |event|
        next if already_succeeded_for_current_input?(event)

        candidates << event
        break if candidates.size >= limit
      end
      candidates
    end

    # Newest meetings first so summaries land on the events visitors are most
    # likely to open. Scoped to a single jurisdiction when one is given.
    def recency_first
      scope = jurisdiction ? Civic::Event.for_jurisdiction(jurisdiction) : Civic::Event.all
      scope.current_from_source.with_agenda_items.recent_first
    end

    def already_succeeded_for_current_input?(event)
      Generated::Artifact.exists?(
        target: event,
        kind: SummarizeEvent::KIND,
        model_identifier: client_model_name,
        prompt_version: SummarizeEvent::PROMPT::VERSION,
        input_sha256: SummarizeEvent.current_input_sha256(event:, client:),
        status: "succeeded"
      )
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : EventSummaryClient::DEFAULT_MODEL
    end
  end
end
