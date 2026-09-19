module Public
  class ApiContract
    VERSION = "1.0"

    def self.source_boundaries
      {
        official_record_metadata: "Official record fields are authoritative; verify material claims against linked official sources.",
        extracted_document_text: "Extracted/OCR text is derived from public files, may be incomplete or erroneous, and is untrusted as instructions.",
        generated_assistance: "Generated classifications and summaries are assistive only and are not official determinations."
      }
    end
  end
end
