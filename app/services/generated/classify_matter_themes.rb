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
    PROMPT = Generated::Prompts::MatterThemesV1
    SUMMARY_KIND = "attachment_summary"

    Result = Data.define(:artifact, :created, :skipped, :reason, :theme_slugs)

    def self.call(matter:, client: ThemesClient.new, force: false)
      new(matter:, client:, force:).call
    end

    def initialize(matter:, client:, force:)
      @matter = matter
      @client = client
      @force = force
    end

    def call
      prompt = PROMPT.build(matter:, source_text:, max_input_chars: client_max_input_chars)
      artifact = find_or_initialize_artifact(input_sha256: prompt[:sent_content_sha256])

      if artifact.persisted? && !force && artifact.status == "succeeded"
        return Result.new(artifact:, created: false, skipped: true, reason: "already_generated", theme_slugs: projected_slugs)
      end

      response = client.call(system_prompt: prompt[:system_prompt], user_prompt: prompt[:user_prompt])
      slugs = Array(response.content["themes"])

      artifact.assign_attributes(
        status: "succeeded",
        content: { "themes" => slugs },
        input_metadata: input_metadata(prompt),
        usage_metadata: response.usage_metadata,
        generated_at: Time.current,
        error_message: nil
      )
      artifact.save!
      sync_projection(artifact, slugs)

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: nil, theme_slugs: slugs)
    rescue StandardError => error
      record_failure(prompt:, error:)
    end

    private

    attr_reader :matter, :client, :force

    def record_failure(prompt:, error:)
      artifact = find_or_initialize_artifact(input_sha256: prompt[:sent_content_sha256])
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
    rescue StandardError => bookkeeping_error
      Rails.logger.error(
        "Generated::ClassifyMatterThemes failed to record failure for " \
        "matter=#{matter.id}: #{bookkeeping_error.class}: #{bookkeeping_error.message}; " \
        "original error: #{error.class}: #{error.message}"
      )
      raise error
    end

    # Replace the matter's projected themes with exactly the returned slugs,
    # stamping the artifact that produced them.
    def sync_projection(artifact, slugs)
      Civic::MatterTheme.transaction do
        matter.themes.where.not(theme_slug: slugs).delete_all
        existing = matter.themes.pluck(:theme_slug)
        (slugs - existing).each do |slug|
          matter.themes.create!(theme_slug: slug, source_artifact_id: artifact.id)
        end
        matter.themes.where(theme_slug: slugs).update_all(source_artifact_id: artifact.id) if slugs.any?
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
        prompt_version: PROMPT::VERSION,
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

      Generated::Prompts::MatterThemesV1::DEFAULT_MAX_INPUT_CHARS
    end
  end
end
