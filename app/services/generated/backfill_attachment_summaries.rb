module Generated
  class BackfillAttachmentSummaries
    DEFAULT_LIMIT = 10

    Result = Data.define(:dry_run, :candidates, :generated, :failed, :skipped)

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, client: SummaryClient.new, force: false)
      new(limit:, dry_run:, client:, force:).call
    end

    def initialize(limit:, dry_run:, client:, force:)
      @limit = limit.to_i
      @dry_run = dry_run
      @client = client
      @force = force
    end

    def call
      candidates = candidate_attachments
      generated = 0
      failed = 0
      skipped = 0

      unless dry_run
        candidates.each do |attachment|
          result = SummarizeMatterAttachment.call(matter_attachment: attachment, client:, force:)
          if result.artifact.status == "succeeded"
            generated += 1
          elsif result.skipped
            skipped += 1
          else
            failed += 1
          end
        end
      end

      Result.new(dry_run:, candidates:, generated:, failed:, skipped:)
    end

    private

    attr_reader :limit, :dry_run, :client, :force

    def candidate_attachments
      base_scope = Civic::MatterAttachment
        .joins(:extracted_texts)
        .merge(Documents::ExtractedText.successful.with_content)
        .includes(:matter)
        .distinct
        .order(:id)

      attachments = force ? base_scope : base_scope.reject { |attachment| generated_for_current_model?(attachment) }
      attachments.first(limit)
    end

    def generated_for_current_model?(attachment)
      attachment.generated_artifacts.exists?(
        kind: SummarizeMatterAttachment::KIND,
        model_identifier: client_model_name,
        prompt_version: SummarizeMatterAttachment::PROMPT::VERSION,
        status: "succeeded"
      )
    end

    def client_model_name
      client.respond_to?(:model_name) ? client.model_name : SummaryClient::DEFAULT_MODEL
    end
  end
end
