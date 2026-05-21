require "digest"

module Generated
  # Classifies a Civic::Matter into one or more themes from the closed
  # Civic::ThemeTaxonomy. Writes the model output to a generated_artifacts row
  # (kind "matter_themes") for provenance and idempotency, then projects the
  # resulting slugs into the civic_matter_themes table that the Pulse
  # aggregation queries.
  #
  # Mirrors Generated::SummarizeMatterAttachment in shape. The matter title and
  # file are always available, so there is no missing-source failure path; when
  # no attachment text exists the model classifies from the identifiers alone.
  class ClassifyMatterThemes
    KIND = "matter_themes"
    SUMMARY_KIND = "attachment_summary"

    # The prompt (and its VERSION, part of the artifact idempotency key) is
    # resolved by the matter's jurisdiction so each jurisdiction classifies
    # against its own vocabulary without colliding with another's artifacts.
    PROMPTS_BY_JURISDICTION = {
      "sanjose" => Generated::Prompts::MatterThemesV1,
      "sjusd" => Generated::Prompts::SjusdMatterThemesV1
    }.freeze
    DEFAULT_PROMPT = Generated::Prompts::MatterThemesV1

    def self.prompt_for(matter)
      slug = matter.civic_jurisdiction&.slug
      PROMPTS_BY_JURISDICTION.fetch(slug, DEFAULT_PROMPT)
    end

    # Procedural/administrative matter types carry no substantive subject. We
    # force them to an empty theme set without calling the model, because the
    # model otherwise classifies them by the content they reference (a closed
    # session "about" litigation, a travel request "about" the trip's topic).
    # This is more reliable than any prompt instruction.
    PROCEDURAL_MATTER_TYPES = [
      "Closed Session Agenda",
      "Approval of Council Committee Minutes",
      "Approval of Council Minutes",
      "Review Final Agenda",
      "Review Draft Agenda",
      "Joint Meeting Agenda",
      "Orders of the Day",
      "Ceremonial Item",
      "Mayor & Council Excused Absence Request"
    ].freeze

    # Travel authorizations are not their own matter type (they ride Consent and
    # Rules Committee types alongside substantive items), so we match them by
    # title instead.
    PROCEDURAL_TITLE_PATTERN = /travel authoriz|request to travel/i

    # Stable input hash for procedurally-skipped matters: the idempotency key
    # already includes the (unique) target, so a constant is safe and lets the
    # backfill recognize a skipped matter as already done without rebuilding a
    # prompt.
    PROCEDURAL_INPUT_SHA256 = Digest::SHA256.hexdigest("procedural:matter_themes").freeze

    Result = Data.define(:artifact, :created, :skipped, :reason, :theme_slugs)

    def self.call(matter:, client: ThemesClient.new, force: false)
      new(matter:, client:, force:).call
    end

    def self.current_input_sha256(matter:, client: ThemesClient.new)
      new(matter:, client:, force: false).current_input_sha256
    end

    def initialize(matter:, client:, force:)
      @matter = matter
      @client = client
      @force = force
    end

    def call
      return classify_procedural if procedural?

      prompt = prompt_class.build(matter:, source_text:, max_input_chars: client_max_input_chars)
      artifact = find_or_initialize_artifact(input_sha256: prompt[:sent_content_sha256])

      if artifact.persisted? && !force && artifact.status == "succeeded"
        return Result.new(artifact:, created: false, skipped: true, reason: "already_generated", theme_slugs: projected_slugs)
      end

      response = client.call(system_prompt: prompt[:system_prompt], user_prompt: prompt[:user_prompt])
      slugs = valid_slugs(response.content["themes"])

      artifact.assign_attributes(
        status: "succeeded",
        content: { "themes" => slugs },
        input_metadata: input_metadata(prompt),
        usage_metadata: response.usage_metadata,
        generated_at: Time.current,
        error_message: nil
      )
      persist_classification(artifact, slugs)

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: nil, theme_slugs: slugs)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent run inserted this matter's artifact between our
      # find_or_initialize and save (e.g. the recurring backfill overlapping a
      # manual run). Adopt it rather than failing; the idempotency key guarantees
      # the other run is equivalent.
      adopt_raced_artifact(input_sha256: prompt[:sent_content_sha256])
    rescue StandardError => error
      record_failure(prompt:, error:)
    end

    def current_input_sha256
      return PROCEDURAL_INPUT_SHA256 if procedural?

      prompt_class.build(matter:, source_text:, max_input_chars: client_max_input_chars)[:sent_content_sha256]
    end

    private

    attr_reader :matter, :client, :force

    def prompt_class
      self.class.prompt_for(matter)
    end

    # Drop any slug the model returned that is not in this matter's jurisdiction
    # vocabulary (the client is taxonomy-agnostic), normalizing case and
    # de-duplicating. Order is preserved so rank 1 stays the model's first pick.
    def valid_slugs(raw)
      Array(raw)
        .map { |slug| slug.to_s.strip.downcase }
        .select { |slug| Civic::ThemeTaxonomy.valid_slug?(slug, matter.civic_jurisdiction) }
        .uniq
    end

    def procedural?
      PROCEDURAL_MATTER_TYPES.include?(matter.matter_type_name) ||
        PROCEDURAL_TITLE_PATTERN.match?("#{matter.title} #{matter.name}")
    end

    # Record a succeeded, empty-theme artifact for a procedural matter without
    # calling the model, and clear any prior projection.
    def classify_procedural
      artifact = find_or_initialize_artifact(input_sha256: PROCEDURAL_INPUT_SHA256)

      if artifact.persisted? && !force && artifact.status == "succeeded"
        return Result.new(artifact:, created: false, skipped: true, reason: "already_generated", theme_slugs: [])
      end

      artifact.assign_attributes(
        status: "succeeded",
        content: { "themes" => [] },
        input_metadata: { "procedural" => true, "matter_type_name" => matter.matter_type_name },
        usage_metadata: {},
        generated_at: Time.current,
        error_message: nil
      )
      persist_classification(artifact, [])

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: "procedural", theme_slugs: [])
    rescue ActiveRecord::RecordNotUnique
      adopt_raced_artifact(input_sha256: PROCEDURAL_INPUT_SHA256)
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

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: "failed", theme_slugs: [])
    rescue ActiveRecord::RecordNotUnique
      adopt_raced_artifact(input_sha256: prompt[:sent_content_sha256])
    rescue StandardError => bookkeeping_error
      Rails.logger.error(
        "Generated::ClassifyMatterThemes failed to record failure for " \
        "matter=#{matter.id}: #{bookkeeping_error.class}: #{bookkeeping_error.message}; " \
        "original error: #{error.class}: #{error.message}"
      )
      raise error
    end

    # A concurrent run already wrote the artifact for this exact (target, kind,
    # model, prompt_version, input) key. Adopt the persisted row rather than
    # clobbering it; the idempotency key guarantees the other run is equivalent
    # to this one, so its themes (or empty set) stand.
    def adopt_raced_artifact(input_sha256:)
      artifact = find_or_initialize_artifact(input_sha256:)
      Result.new(
        artifact:,
        created: false,
        skipped: true,
        reason: "raced",
        theme_slugs: Array(artifact.content&.dig("themes"))
      )
    end

    # Persist the artifact and its civic_matter_themes projection atomically, so
    # a "succeeded" artifact can never exist without its matching projection. If
    # the projection write fails, the artifact save rolls back too and the error
    # propagates to record_failure (which then writes a failed artifact rather
    # than leaving a half-applied success). This is also what makes the
    # record_failure no-downgrade guard unambiguous: a succeeded artifact found
    # there can only belong to another process, never a half-done current run.
    def persist_classification(artifact, slugs)
      ActiveRecord::Base.transaction do
        artifact.save!
        sync_projection(artifact, slugs)
      end
    end

    # Replace the matter's projected themes with exactly the returned slugs,
    # stamping the artifact that produced them. The model returns themes most
    # central first, so the array index becomes a 1-based rank (rank 1 is the
    # matter's primary theme), which the pulse uses to count matters under their
    # primary theme rather than every incidental tag.
    def sync_projection(artifact, slugs)
      Civic::MatterTheme.transaction do
        slugs.each_with_index do |slug, index|
          theme = matter.themes.find_or_initialize_by(theme_slug: slug)
          theme.assign_attributes(rank: index + 1, source_artifact_id: artifact.id)
          theme.save!
        end
        matter.themes.where.not(theme_slug: slugs).delete_all
      end
    end

    def projected_slugs
      matter.themes.pluck(:theme_slug)
    end

    # Source material for classification: prefer existing attachment summaries
    # (cheap, high-signal), fall back to the latest extracted text per
    # attachment. The matter identifiers are added by the prompt builder.
    def source_text
      @source_text ||= summary_source_text.presence || extracted_source_text
    end

    def summary_source_text
      matter.attachments.filter_map do |attachment|
        content = latest_summary_content(attachment)
        next unless content

        lines = [ "#{attachment.name}: #{content['summary']}" ]
        Array(content["key_points"]).each { |point| lines << "- #{point}" }
        lines.join("\n")
      end.join("\n\n")
    end

    def extracted_source_text
      matter.attachments.filter_map do |attachment|
        text = attachment.latest_extracted_text
        next unless text&.status == "ok" && text.content.present?

        "#{attachment.name}: #{text.content}"
      end.join("\n\n")
    end

    def latest_summary_content(attachment)
      attachment.generated_artifacts
        .succeeded
        .for_kind(SUMMARY_KIND)
        .order(created_at: :desc, id: :desc)
        .first
        &.content
    end

    def find_or_initialize_artifact(input_sha256:)
      Generated::Artifact.find_or_initialize_by(
        target: matter,
        kind: KIND,
        model_identifier: client_model_name,
        prompt_version: prompt_class::VERSION,
        input_sha256:
      )
    end

    def input_metadata(prompt)
      {
        "sent_character_count" => prompt[:sent_character_count],
        "sent_content_sha256" => prompt[:sent_content_sha256],
        "truncated" => prompt[:truncated]
      }
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : ThemesClient::DEFAULT_MODEL
    end

    def client_max_input_chars
      return client.max_input_chars if client.respond_to?(:max_input_chars)

      Generated::Prompts::MatterThemesBase::DEFAULT_MAX_INPUT_CHARS
    end
  end
end
