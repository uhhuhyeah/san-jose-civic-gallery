module ApplicationHelper
  DEFAULT_PAGE_TITLE = "San Jose Civic Gallery"
  DEFAULT_PAGE_DESCRIPTION = "San Jose Civic Gallery helps residents browse San Jose City Hall agendas, matters, attachments, minutes, extracted document text, and official source links."
  OFFICIAL_SOURCE_HOSTS = %w[
    sanjose.legistar.com
    www.sanjoseca.gov
    simbli.eboardsolutions.com
  ].freeze
  EXTRACTED_TEXT_PREVIEW_LENGTH = 1_200
  DOCUMENT_SEARCH_SNIPPET_LENGTH = 320
  GENERATED_SUMMARY_KIND = Generated::SummarizeMatterAttachment::KIND
  GENERATED_SUMMARY_PROMPT_VERSION = Generated::SummarizeMatterAttachment::PROMPT::VERSION

  def page_title
    title = content_for(:title).presence
    return DEFAULT_PAGE_TITLE if title.blank? || title == DEFAULT_PAGE_TITLE

    "#{title} | #{DEFAULT_PAGE_TITLE}"
  end

  def page_description
    content_for(:description).presence || DEFAULT_PAGE_DESCRIPTION
  end

  def official_source_url(raw_url)
    return if raw_url.blank?

    uri = URI.parse(raw_url.to_s.strip)
    return unless uri.is_a?(URI::HTTPS)
    return unless OFFICIAL_SOURCE_HOSTS.include?(uri.host)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def attachment_import_status(attachment)
    if attachment.imported?
      size = number_to_human_size(attachment.source_file_byte_size || attachment.source_file.blob.byte_size)
      "File imported (#{size})"
    elsif attachment.source_file_import_error.present?
      "File import failed"
    else
      "File not imported yet"
    end
  end

  def attachment_extraction_status(attachment)
    case attachment.extraction_status
    when "ok"
      return "OCR text available" if attachment.latest_extracted_text&.extractor_name == Documents::OcrPdfText::EXTRACTOR_NAME

      "Extracted text available"
    when "empty"
      "Extraction completed with no text"
    when "error"
      "Text extraction failed"
    when "pending"
      "Text extraction pending"
    else
      "Text extraction not available"
    end
  end

  def extracted_text_preview(extracted_text)
    return "" if extracted_text&.content.blank?

    truncate(extracted_text.content.squish, length: EXTRACTED_TEXT_PREVIEW_LENGTH, separator: " ")
  end

  # Filter in Ruby (not via Generated::Artifact.succeeded.for_kind) so the
  # controller preload on :generated_artifacts is preserved. Adding scoped
  # queries here would issue a fresh SELECT per attachment and reintroduce
  # the N+1 the preload was added to avoid.
  def attachment_summary_artifact(attachment)
    attachment
      .generated_artifacts
      .select do |artifact|
        artifact.kind == GENERATED_SUMMARY_KIND &&
          artifact.prompt_version == GENERATED_SUMMARY_PROMPT_VERSION &&
          artifact.status == "succeeded"
      end
      .max_by { |artifact| [ artifact.generated_at || artifact.created_at, artifact.id ] }
  end

  def attachment_summary_state(attachment, summary_artifact = attachment_summary_artifact(attachment))
    return :available if summary_artifact

    latest_text = attachment.latest_extracted_text
    return :pending if latest_text&.status == "ok" && latest_text.content.present?

    :not_available
  end

  def attachment_summary_status_text(attachment, summary_artifact = attachment_summary_artifact(attachment))
    case attachment_summary_state(attachment, summary_artifact)
    when :available
      "Generated summary available"
    when :pending
      "Generated summary pending"
    else
      "Generated summary not available"
    end
  end

  # Only meaningful when the state is :not_available — the view branches on
  # :available and :pending before calling this.
  def attachment_summary_not_available_reason(attachment)
    latest_text = attachment.latest_extracted_text

    return "The source file has not been imported yet." unless attachment.imported?
    return "Text extraction failed for this attachment." if latest_text&.status == "error"
    return "Extraction completed, but no usable text was found." if latest_text&.status == "empty"

    "No extracted text is available yet."
  end

  def document_search_snippet(extracted_text)
    if (snippet = extracted_text.try(:search_snippet).presence)
      sanitize(snippet, tags: %w[mark], attributes: [])
    else
      sanitize(truncate(extracted_text&.content.to_s.squish, length: DOCUMENT_SEARCH_SNIPPET_LENGTH, separator: " "))
    end
  end
end
