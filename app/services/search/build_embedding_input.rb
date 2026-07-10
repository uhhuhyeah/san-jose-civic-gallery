module Search
  # Builds the text input to be embedded from a generated artifact.
  # Structured text produces better embeddings than raw JSON.
  class BuildEmbeddingInput
    def self.call(artifact)
      new(artifact).call
    end

    def initialize(artifact)
      @artifact = artifact
    end

    def call
      case @artifact.kind
      when "attachment_summary"
        build_from_attachment_summary
      when "event_summary"
        build_from_event_summary
      else
        raise ArgumentError, "Unknown artifact kind for embedding: #{@artifact.kind}"
      end
    end

    private

    def build_from_attachment_summary
      content = @artifact.content
      lines = []
      lines << "Summary: #{content["summary"]}"
      lines << ""
      lines << "Key points:"
      Array(content["key_points"]).each { |pt| lines << "- #{pt}" }
      lines << ""
      lines << "Limitations:"
      Array(content["limitations"]).each { |lim| lines << "- #{lim}" }
      lines << ""
      lines << "Document status: #{content["document_status"]}"
      lines.join("\n")
    end

    def build_from_event_summary
      content = @artifact.content
      lines = []
      lines << "Summary: #{content["summary"]}"
      lines << ""
      lines << "Key topics:"
      Array(content["key_topics"]).each { |topic| lines << "- #{topic}" }
      lines << ""
      lines << "Limitations:"
      Array(content["limitations"]).each { |lim| lines << "- #{lim}" }
      lines.join("\n")
    end
  end
end
