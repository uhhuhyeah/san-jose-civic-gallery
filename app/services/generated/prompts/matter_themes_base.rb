require "digest"

module Generated
  module Prompts
    # Shared mechanics for the matter-theme classification prompts. Subclasses
    # supply a VERSION, a #system_prompt, and a #taxonomy (the jurisdiction's
    # Civic::ThemeTaxonomy list). The user prompt, input hashing, and truncation
    # are identical across jurisdictions, so they live here.
    #
    # The idempotency hash (#sent_content) covers matter identity and source
    # text only, not the system prompt; the prompt VERSION (resolved per
    # jurisdiction) is the part of the artifact key that changes when the
    # instructions or taxonomy change.
    class MatterThemesBase
      DEFAULT_MAX_INPUT_CHARS = 12_000
      TRUNCATION_MARKER = "\n\n…[truncated]".freeze
      NO_BODY_TEXT = "(No attachment text available; classify from the title and name only.)".freeze

      def self.build(matter:, source_text:, max_input_chars: DEFAULT_MAX_INPUT_CHARS)
        new(matter:, source_text:, max_input_chars:).build
      end

      def initialize(matter:, source_text:, max_input_chars:)
        @matter = matter
        @source_text = source_text.to_s
        @max_input_chars = max_input_chars.to_i
      end

      def build
        {
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          sent_content: sent_content,
          sent_character_count: sent_content.length,
          sent_content_sha256: Digest::SHA256.hexdigest(sent_content),
          truncated: truncated?
        }
      end

      private

      attr_reader :matter, :source_text, :max_input_chars

      # Subclasses must implement.
      def system_prompt
        raise NotImplementedError, "#{self.class} must define #system_prompt"
      end

      # Subclasses must return the jurisdiction's Civic::ThemeTaxonomy list.
      def taxonomy
        raise NotImplementedError, "#{self.class} must define #taxonomy"
      end

      def user_prompt
        <<~PROMPT
          Matter file: #{matter.matter_file}
          Matter title: #{matter.descriptive_title}

          <source_text>
          #{body_text}
          </source_text>
        PROMPT
      end

      def taxonomy_lines
        taxonomy
          .map { |theme| "- #{theme[:slug]} — #{theme[:label]}" }
          .join("\n")
      end

      # Hash the full classification-relevant input (identity + body) so the
      # idempotency key changes when either the matter identity or the source
      # text changes.
      def sent_content
        @sent_content ||= [
          matter.matter_file,
          matter.descriptive_title,
          body_text
        ].map(&:to_s).join("\n")
      end

      def body_text
        @body_text ||= begin
          trimmed = source_text.strip
          return NO_BODY_TEXT if trimmed.blank?

          trimmed.length > max_input_chars ? trimmed[0, max_input_chars] + TRUNCATION_MARKER : trimmed
        end
      end

      def truncated?
        source_text.strip.length > max_input_chars
      end
    end
  end
end
