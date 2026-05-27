require "digest"

module Generated
  # Summarizes a full month of civic activity into a monthly roundup
  # generated_artifacts row (kind "monthly_roundup"). The data comes from
  # Public::MonthlyActivity (decisions, introductions, meetings, theme
  # momentum, quiet-month flag). The prompt renderer handles quiet months
  # gracefully, so there is no missing-source skip.
  #
  # Mirrors Generated::SummarizeEvent in shape: idempotent artifact write
  # keyed by (target, kind, model, prompt_version, input_sha256), race
  # adoption, and no-downgrade failure recording.
  class SummarizeRoundup
    KIND = "monthly_roundup"
    PROMPT = Generated::Prompts::MonthlyRoundupV1

    Result = Data.define(:artifact, :created, :skipped, :reason)

    def self.call(period:, activity: nil, client: RoundupClient.new, force: false)
      new(period:, activity:, client:, force:).call
    end

    def self.current_input_sha256(period:, activity: nil, client: RoundupClient.new)
      new(period:, activity:, client:, force: false).current_input_sha256
    end

    def initialize(period:, activity:, client:, force:)
      @period = period
      @client = client
      @force = force
      @activity = activity || Public::MonthlyActivity.new(
        jurisdiction: period.civic_jurisdiction,
        period_start: period.period_start,
        period_end: period.period_end
      )
    end

    def call
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
      build_prompt[:sent_content_sha256]
    end

    private

    attr_reader :period, :client, :force, :activity

    def build_prompt
      @build_prompt ||= PROMPT.build(
        period:,
        activity:,
        max_input_chars: client_max_input_chars
      )
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
        "Generated::SummarizeRoundup failed to record failure for " \
        "period=#{period.id}: #{bookkeeping_error.class}: #{bookkeeping_error.message}; " \
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
        target: period,
        kind: KIND,
        model_identifier: client_model_name,
        prompt_version: PROMPT::VERSION,
        input_sha256:
      )
    end

    def input_metadata(prompt)
      {
        "decision_count" => activity.decisions.size,
        "introduced_count" => activity.introduced.size,
        "meeting_count" => activity.meetings.size,
        "quiet_month" => activity.quiet_month?,
        "sent_character_count" => prompt[:sent_character_count],
        "sent_content_sha256" => prompt[:sent_content_sha256],
        "truncated" => prompt[:truncated]
      }
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : RoundupClient::DEFAULT_MODEL
    end

    def client_max_input_chars
      return client.max_input_chars if client.respond_to?(:max_input_chars)

      Generated::Prompts::MonthlyRoundupV1::DEFAULT_MAX_INPUT_CHARS
    end
  end
end
