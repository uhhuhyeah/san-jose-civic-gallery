module Generated
  module Prompts
    class AttachmentSummaryV1
      VERSION = "attachment_summary_v1"
      DEFAULT_MAX_INPUT_CHARS = 18_000

      def self.build(matter_attachment:, extracted_text:, max_input_chars: DEFAULT_MAX_INPUT_CHARS)
        new(matter_attachment:, extracted_text:, max_input_chars:).build
      end

      def initialize(matter_attachment:, extracted_text:, max_input_chars:)
        @matter_attachment = matter_attachment
        @extracted_text = extracted_text
        @max_input_chars = max_input_chars.to_i
      end

      def build
        {
          system_prompt:,
          user_prompt:
        }
      end

      private

      attr_reader :matter_attachment, :extracted_text, :max_input_chars

      def system_prompt
        <<~PROMPT
          You summarize official civic attachment text for public readers.
          Use only facts present in the supplied extracted text.
          Do not infer unstated dates, votes, dollar amounts, parties, or outcomes.
          If extraction quality is poor or the text is too sparse, say so in limitations.
          Return only valid JSON with keys: summary, key_points, limitations.
        PROMPT
      end

      def user_prompt
        <<~PROMPT
          Attachment name: #{matter_attachment.name}
          Matter file: #{matter_attachment.matter.matter_file}
          Source extractor: #{extracted_text.extractor_name}
          Source checksum: #{extracted_text.source_file_checksum_sha256}

          Extracted text:
          #{truncated_content}
        PROMPT
      end

      def truncated_content
        extracted_text.content.to_s.first(max_input_chars)
      end
    end
  end
end
