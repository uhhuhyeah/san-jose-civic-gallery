require "digest"

module Generated
  class SummarizeMatterAttachment
    KIND = "attachment_summary"
    PROMPT = Generated::Prompts::AttachmentSummaryV1
    MISSING_SOURCE_INPUT_SHA256 = Digest::SHA256.hexdigest("missing_source_text").freeze

    Result = Data.define(:artifact, :created, :skipped, :reason)

    def self.call(matter_attachment:, client: SummaryClient.new, force: false)
      new(matter_attachment:, client:, force:).call
    end

    def initialize(matter_attachment:, client:, force:)
      @matter_attachment = matter_attachment
      @client = client
      @force = force
    end

    def call
      extracted_text = latest_source_text
      return missing_source_artifact unless extracted_text

      generate_with(extracted_text)
    end

    private

    attr_reader :matter_attachment, :client, :force

    def generate_with(extracted_text)
      prompt = PROMPT.build(
        matter_attachment:,
        extracted_text:,
        max_input_chars: client_max_input_chars
      )
      artifact = find_or_initialize_artifact(input_sha256: prompt[:sent_content_sha256])
      if artifact.persisted? && !force && artifact.status == "succeeded"
        return Result.new(artifact:, created: false, skipped: true, reason: "already_generated")
      end

      response = client.call(system_prompt: prompt[:system_prompt], user_prompt: prompt[:user_prompt])
      artifact.assign_attributes(
        source_artifact: extracted_text,
        status: "succeeded",
        content: response.content,
        input_metadata: input_metadata(extracted_text, prompt),
        generated_at: Time.current,
        error_message: nil
      )
      artifact.save!

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: nil)
    rescue StandardError => error
      record_failure(extracted_text:, prompt:, error:)
    end

    def record_failure(extracted_text:, prompt:, error:)
      input_sha256 = prompt&.fetch(:sent_content_sha256, nil) || MISSING_SOURCE_INPUT_SHA256
      artifact = find_or_initialize_artifact(input_sha256:)
      artifact.assign_attributes(
        source_artifact: extracted_text,
        status: "failed",
        content: {},
        input_metadata: prompt ? input_metadata(extracted_text, prompt) : { "reason" => "prompt_build_failed" },
        generated_at: Time.current,
        error_message: error.message
      )
      artifact.save!

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: "failed")
    rescue StandardError => bookkeeping_error
      Rails.logger.error(
        "Generated::SummarizeMatterAttachment failed to record summary failure for " \
        "matter_attachment=#{matter_attachment.id}: " \
        "#{bookkeeping_error.class}: #{bookkeeping_error.message}; " \
        "original error: #{error.class}: #{error.message}"
      )
      raise error
    end

    def latest_source_text
      matter_attachment.extracted_texts.successful.with_content.recent_first.first
    end

    def missing_source_artifact
      artifact = find_or_initialize_artifact(input_sha256: MISSING_SOURCE_INPUT_SHA256)
      return Result.new(artifact:, created: false, skipped: true, reason: "missing_source_text") if artifact.persisted?

      artifact.assign_attributes(
        status: "failed",
        content: {},
        input_metadata: { "reason" => "missing_source_text" },
        generated_at: Time.current,
        error_message: "No successful extracted text is available for this attachment."
      )
      artifact.save!

      Result.new(artifact:, created: true, skipped: false, reason: "missing_source_text")
    end

    def find_or_initialize_artifact(input_sha256:)
      # Idempotency comes from the unique (target, kind, model_identifier,
      # prompt_version, input_sha256) constraint. Anything embedded in
      # input_sha256 that's already in the constraint is redundant, so we
      # only hash content-bearing inputs (handled by the prompt builder).
      Generated::Artifact.find_or_initialize_by(
        target: matter_attachment,
        kind: KIND,
        model_identifier: client_model_name,
        prompt_version: PROMPT::VERSION,
        input_sha256:
      )
    end

    def input_metadata(extracted_text, prompt)
      {
        "source_artifact_type" => extracted_text.class.name,
        "source_artifact_id" => extracted_text.id,
        "extractor_name" => extracted_text.extractor_name,
        "extractor_version" => extracted_text.extractor_version,
        "source_file_checksum_sha256" => extracted_text.source_file_checksum_sha256,
        "extracted_character_count" => extracted_text.character_count,
        "sent_character_count" => prompt[:sent_character_count],
        "sent_content_sha256" => prompt[:sent_content_sha256],
        "truncated" => prompt[:truncated]
      }
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : SummaryClient::DEFAULT_MODEL
    end

    def client_max_input_chars
      return client.max_input_chars if client.respond_to?(:max_input_chars)

      Generated::Prompts::AttachmentSummaryV1::DEFAULT_MAX_INPUT_CHARS
    end
  end
end
