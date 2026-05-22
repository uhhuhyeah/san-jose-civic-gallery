require "digest"

module Generated
  # Summarizes a single Civic::Event from its own item record into a
  # generated_artifacts row (kind "event_summary"). The summary orients a
  # reader to the topics a meeting took up; it never states outcomes (that
  # rule lives in the prompt).
  #
  # Mirrors Generated::SummarizeMatterAttachment in shape: idempotent artifact
  # write keyed by (target, kind, model, prompt_version, input_sha256), a
  # stable missing-source skip, race adoption, and no-downgrade failure
  # recording. The hashed input is the event identity plus the assembled item
  # digest, so a summary regenerates only when the event's item set changes,
  # not when a linked matter's themes are reclassified.
  class SummarizeEvent
    KIND = "event_summary"
    PROMPT = Generated::Prompts::EventSummaryV1
    PER_ITEM_NOTE_LIMIT = 1_000
    MISSING_SOURCE_INPUT_SHA256 = Digest::SHA256.hexdigest("event_summary:missing_source").freeze

    Result = Data.define(:artifact, :created, :skipped, :reason)

    def self.call(event:, client: EventSummaryClient.new, force: false)
      new(event:, client:, force:).call
    end

    def self.current_input_sha256(event:, client: EventSummaryClient.new)
      new(event:, client:, force: false).current_input_sha256
    end

    def initialize(event:, client:, force:)
      @event = event
      @client = client
      @force = force
    end

    def call
      return missing_source_artifact if source_text.blank?

      prompt = build_prompt
      artifact = find_or_initialize_artifact(input_sha256: prompt[:sent_content_sha256])

      if artifact.persisted? && !force && artifact.status == "succeeded"
        return Result.new(artifact:, created: false, skipped: true, reason: "already_generated")
      end

      response = client.call(system_prompt: prompt[:system_prompt], user_prompt: prompt[:user_prompt])

      artifact.assign_attributes(
        status: "succeeded",
        content: response.content,
        input_metadata: input_metadata(prompt),
        usage_metadata: response.usage_metadata,
        generated_at: Time.current,
        error_message: nil
      )
      artifact.save!

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: nil)
    rescue ActiveRecord::RecordNotUnique
      adopt_raced_artifact(input_sha256: prompt[:sent_content_sha256])
    rescue StandardError => error
      record_failure(prompt:, error:)
    end

    def current_input_sha256
      return MISSING_SOURCE_INPUT_SHA256 if source_text.blank?

      build_prompt[:sent_content_sha256]
    end

    private

    attr_reader :event, :client, :force

    def build_prompt
      @build_prompt ||= PROMPT.build(
        event:,
        source_text:,
        theme_summary:,
        max_input_chars: client_max_input_chars
      )
    end

    # Source text is the meeting's own item record: the recorded minutes note
    # per item (the discussion record), falling back to the agenda note. The
    # subject is taken from the item or matter title. Outcomes that appear in
    # the note are left for the model to ignore per its instructions.
    def source_text
      @source_text ||= event_items.filter_map { |item| item_record(item) }.join("\n\n")
    end

    def item_record(item)
      note = item_note(item)
      subject = item_subject(item)
      return nil if note.blank? && subject.blank?

      heading = [ item.agenda_number.presence, subject ].compact_blank.join(" ").presence || "Item"
      [ heading, note ].compact_blank.join("\n")
    end

    def item_subject(item)
      [ item.title, item.matter&.descriptive_title, item.matter_name ]
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
        .uniq
        .first
    end

    def item_note(item)
      raw = item.minutes_note.presence || item.agenda_note.presence
      return nil if raw.blank?

      trimmed = raw.strip
      trimmed.length > PER_ITEM_NOTE_LIMIT ? "#{trimmed[0, PER_ITEM_NOTE_LIMIT]}…" : trimmed
    end

    # Advisory theme hint, kept out of the idempotency hash by the prompt
    # builder. Lists each item's classified themes so the model can prioritize
    # substantive, theme-linked items over procedural ones.
    def theme_summary
      @theme_summary ||= event_items.filter_map { |item| item_theme_line(item) }.join("\n")
    end

    def item_theme_line(item)
      return nil unless item.matter

      label = item.agenda_number.presence || item.display_name
      ranked = item.matter.themes.sort_by { |theme| theme.rank || Float::INFINITY }
      labels = ranked.map(&:label).compact
      theme_text = labels.present? ? labels.join(", ") : "none (likely procedural)"
      "- #{label}: #{theme_text}"
    end

    def event_items
      @event_items ||= event.event_items.includes(matter: :themes).to_a
    end

    def missing_source_artifact
      artifact = find_or_initialize_artifact(input_sha256: MISSING_SOURCE_INPUT_SHA256)
      return Result.new(artifact:, created: false, skipped: true, reason: "missing_source_text") if artifact.persisted?

      artifact.assign_attributes(
        status: "failed",
        content: {},
        input_metadata: { "reason" => "missing_source_text" },
        usage_metadata: {},
        generated_at: Time.current,
        error_message: "No agenda or minutes item text is available for this event."
      )
      artifact.save!

      Result.new(artifact:, created: true, skipped: false, reason: "missing_source_text")
    rescue ActiveRecord::RecordNotUnique
      adopt_raced_artifact(input_sha256: MISSING_SOURCE_INPUT_SHA256)
    end

    def record_failure(prompt:, error:)
      artifact = find_or_initialize_artifact(input_sha256: prompt[:sent_content_sha256])

      # A concurrent run may have succeeded between our model call and now.
      # Never downgrade a succeeded artifact to failed; adopt it instead.
      if artifact.persisted? && artifact.status == "succeeded"
        return adopt_raced_artifact(input_sha256: prompt[:sent_content_sha256])
      end

      artifact.assign_attributes(
        status: "failed",
        content: {},
        input_metadata: input_metadata(prompt),
        usage_metadata: {},
        generated_at: Time.current,
        error_message: error.message
      )
      artifact.save!

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: "failed")
    rescue ActiveRecord::RecordNotUnique
      adopt_raced_artifact(input_sha256: prompt[:sent_content_sha256])
    rescue StandardError => bookkeeping_error
      Rails.logger.error(
        "Generated::SummarizeEvent failed to record failure for " \
        "event=#{event.id}: #{bookkeeping_error.class}: #{bookkeeping_error.message}; " \
        "original error: #{error.class}: #{error.message}"
      )
      raise error
    end

    # A concurrent run already wrote the artifact for this exact key. Adopt the
    # persisted row rather than clobbering it; the idempotency key guarantees
    # the other run is equivalent to this one.
    def adopt_raced_artifact(input_sha256:)
      artifact = find_or_initialize_artifact(input_sha256:)
      Result.new(artifact:, created: false, skipped: true, reason: "raced")
    end

    def find_or_initialize_artifact(input_sha256:)
      Generated::Artifact.find_or_initialize_by(
        target: event,
        kind: KIND,
        model_identifier: client_model_name,
        prompt_version: PROMPT::VERSION,
        input_sha256:
      )
    end

    def input_metadata(prompt)
      {
        "item_count" => event_items.size,
        "sent_character_count" => prompt[:sent_character_count],
        "sent_content_sha256" => prompt[:sent_content_sha256],
        "truncated" => prompt[:truncated]
      }
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : EventSummaryClient::DEFAULT_MODEL
    end

    def client_max_input_chars
      return client.max_input_chars if client.respond_to?(:max_input_chars)

      Generated::Prompts::EventSummaryV1::DEFAULT_MAX_INPUT_CHARS
    end
  end
end
