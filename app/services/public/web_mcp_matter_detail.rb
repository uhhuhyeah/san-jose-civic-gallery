require "uri"

module Public
  # The R3 WebMCP detail contract. It serializes only the public detail page's
  # verification-oriented record context; it deliberately excludes raw source
  # snapshots, attachment text, generated content, and operational internals.
  class WebMcpMatterDetail
    CONTRACT_VERSION = "1.0"
    MAX_MEETINGS = 10
    MAX_ATTACHMENTS = 25
    OFFICIAL_SOURCE_HOSTS = ApplicationHelper::OFFICIAL_SOURCE_HOSTS

    class InvalidReference < StandardError; end

    def self.call(reference:, jurisdiction:, request:, routes:)
      new(reference:, jurisdiction:, request:, routes:).call
    end

    def initialize(reference:, jurisdiction:, request:, routes:)
      @reference = reference.to_s
      @jurisdiction = jurisdiction
      @request = request
      @routes = routes
    end

    def call
      matter = resolve_matter
      raise InvalidReference, "matter reference is invalid or unavailable" unless matter

      {
        kind: "civicgallery_matter_detail",
        contract_version: CONTRACT_VERSION,
        jurisdiction: jurisdiction_context,
        matter: matter_context(matter),
        source_boundaries: source_boundaries
      }
    end

    private

    def resolve_matter
      return WebMcpMatterReference.resolve(@reference, jurisdiction: @jurisdiction) unless url_reference?

      uri = URI.parse(@reference)
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      return unless uri.scheme == @request.protocol.delete_suffix("://")
      return unless uri.host.casecmp?(@request.host)
      return unless uri.port == @request.port
      return unless uri.query.blank? && uri.fragment.blank?

      match = %r{\A/public/matters/(\d+)\z}.match(uri.path)
      return unless match

      Civic::Matter.for_jurisdiction(@jurisdiction).find_by(id: match[1])
    rescue URI::InvalidURIError
      nil
    end

    def url_reference?
      @reference.start_with?("http://", "https://")
    end

    def jurisdiction_context
      {
        slug: @jurisdiction.slug,
        name: @jurisdiction.name,
        source_system: @jurisdiction.source_system_default
      }
    end

    def matter_context(matter)
      {
        matter_reference: WebMcpMatterReference.generate(matter),
        matter_identifier: matter.display_name,
        title: matter.descriptive_title,
        body_name: matter.body_name,
        status: matter.matter_status_name,
        matter_type: matter.matter_type_name,
        requester: matter.requester,
        intro_date: matter.intro_date&.iso8601,
        agenda_date: matter.agenda_date&.iso8601,
        enactment_date: matter.enactment_date&.iso8601,
        enactment_number: matter.enactment_number,
        civic_gallery_url: @routes.public_matter_url(matter),
        provenance: "official_record_metadata",
        themes: themes_for(matter),
        meetings: meetings_for(matter),
        attachments: attachments_for(matter)
      }
    end

    def themes_for(matter)
      matter.themes.sort_by(&:rank).map do |theme|
        { slug: theme.theme_slug, label: theme.label, provenance: "generated_assisted_classification" }
      end
    end

    def meetings_for(matter)
      matter.event_items.current_from_source.agenda_order.includes(:event).first(MAX_MEETINGS).map do |item|
        event = item.event
        {
          title: event.display_name,
          body_name: event.body_name,
          event_date: event.event_date&.iso8601,
          agenda_number: item.agenda_number,
          agenda_item_title: item.title,
          civic_gallery_url: @routes.public_event_url(event),
          official_source_url: official_source_url(event.in_site_url),
          provenance: "official_record_metadata"
        }
      end
    end

    def attachments_for(matter)
      matter.attachments.includes(:extracted_texts, :generated_artifacts).first(MAX_ATTACHMENTS).map do |attachment|
        latest_text = attachment.latest_extracted_text
        {
          name: attachment.name,
          file_name: attachment.file_name,
          official_source_url: official_source_url(attachment.hyperlink),
          file_status: file_status(attachment),
          extraction_status: attachment.extraction_status,
          generated_summary_status: generated_summary_status(attachment, latest_text),
          provenance: {
            metadata: "official_record_metadata",
            extraction: "extracted_document_status",
            generated_summary: "generated_assistance_status"
          }
        }
      end
    end

    def file_status(attachment)
      return "imported" if attachment.imported?
      return "import_failed" if attachment.source_file_import_error.present?

      "not_imported"
    end

    def generated_summary_status(attachment, latest_text)
      return "available" if summary_artifact(attachment)
      return "pending" if latest_text&.status == "ok" && latest_text.content.present?

      "not_available"
    end

    def summary_artifact(attachment)
      attachment.generated_artifacts
        .select { |artifact| artifact.kind == ApplicationHelper::GENERATED_SUMMARY_KIND && artifact.prompt_version == ApplicationHelper::GENERATED_SUMMARY_PROMPT_VERSION && artifact.status == "succeeded" }
        .max_by { |artifact| [ artifact.generated_at || artifact.created_at, artifact.id ] }
    end

    def official_source_url(value)
      uri = URI.parse(value.to_s.strip)
      return unless uri.is_a?(URI::HTTPS) && OFFICIAL_SOURCE_HOSTS.include?(uri.host)

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def source_boundaries
      {
        official_record_metadata: "Official record fields; verify material claims against linked official sources.",
        extracted_document_status: "Availability metadata only; extracted document text is intentionally excluded.",
        generated_assisted_classification: "Assistive only and not an official determination.",
        generated_assistance_status: "Availability metadata only; generated summary content is intentionally excluded."
      }
    end
  end
end
