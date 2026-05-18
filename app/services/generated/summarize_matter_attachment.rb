require "digest"

module Generated
  class SummarizeMatterAttachment
    KIND = "attachment_summary"
    PROMPT = Generated::Prompts::AttachmentSummaryV1

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

      prompt = PROMPT.build(
        matter_attachment:,
        extracted_text:,
        max_input_chars: client_max_input_chars
      )
      artifact = find_or_initialize_artifact(extracted_text:)
      return Result.new(artifact:, created: false, skipped: true, reason: "already_generated") if artifact.persisted? && !force

      response = client.call(**prompt)
      artifact.assign_attributes(
        source_artifact: extracted_text,
        status: "succeeded",
        content: response.content,
        input_metadata: input_metadata(extracted_text),
        generated_at: Time.current,
        error_message: nil
      )
      artifact.save!

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: nil)
    rescue StandardError => error
      artifact ||= find_or_initialize_artifact(extracted_text:)
      artifact.assign_attributes(
        source_artifact: extracted_text,
        status: "failed",
        content: {},
        input_metadata: extracted_text ? input_metadata(extracted_text) : {},
        generated_at: Time.current,
        error_message: error.message
      )
      artifact.save!

      Result.new(artifact:, created: artifact.previously_new_record?, skipped: false, reason: "failed")
    end

    private

    attr_reader :matter_attachment, :client, :force

    def latest_source_text
      matter_attachment.extracted_texts.successful.with_content.recent_first.first
    end

    def missing_source_artifact
      artifact = Generated::Artifact.find_or_initialize_by(
        target: matter_attachment,
        kind: KIND,
        model_identifier: client_model_name,
        prompt_version: PROMPT::VERSION,
        input_sha256: missing_source_digest
      )
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

    def find_or_initialize_artifact(extracted_text:)
      Generated::Artifact.find_or_initialize_by(
        target: matter_attachment,
        kind: KIND,
        model_identifier: client_model_name,
        prompt_version: PROMPT::VERSION,
        input_sha256: input_digest(extracted_text)
      )
    end

    def input_digest(extracted_text)
      Digest::SHA256.hexdigest([
        PROMPT::VERSION,
        extracted_text.id,
        extracted_text.extractor_name,
        extracted_text.extractor_version,
        extracted_text.source_file_checksum_sha256,
        extracted_text.content
      ].join("\n"))
    end

    def missing_source_digest
      Digest::SHA256.hexdigest([
        PROMPT::VERSION,
        matter_attachment.class.name,
        matter_attachment.id,
        "missing_source_text"
      ].join("\n"))
    end

    def input_metadata(extracted_text)
      {
        "source_artifact_type" => extracted_text.class.name,
        "source_artifact_id" => extracted_text.id,
        "extractor_name" => extracted_text.extractor_name,
        "extractor_version" => extracted_text.extractor_version,
        "source_file_checksum_sha256" => extracted_text.source_file_checksum_sha256,
        "character_count" => extracted_text.character_count
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
