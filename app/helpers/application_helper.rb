module ApplicationHelper
  OFFICIAL_SOURCE_HOSTS = %w[
    sanjose.legistar.com
    www.sanjoseca.gov
  ].freeze
  EXTRACTED_TEXT_PREVIEW_LENGTH = 1_200
  DOCUMENT_SEARCH_SNIPPET_LENGTH = 320

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

  def document_search_snippet(extracted_text)
    if (snippet = extracted_text.try(:search_snippet).presence)
      sanitize(snippet, tags: %w[mark], attributes: [])
    else
      sanitize(truncate(extracted_text&.content.to_s.squish, length: DOCUMENT_SEARCH_SNIPPET_LENGTH, separator: " "))
    end
  end
end
