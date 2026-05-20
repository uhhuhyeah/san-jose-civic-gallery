module DataHealth
  # Aggregate read model for the public /data transparency page. One
  # method per surfaced metric so each can be tested in isolation. All
  # queries hit indexed columns; numbers are intended to be cached at
  # the HTTP layer via the snapshot's cache_key.
  #
  # Scoped to a single jurisdiction so the /data page on each host reports
  # only that jurisdiction's records.
  class Snapshot
    # Freshness thresholds, tuned for a daily cron. Adjust here when
    # the cadence firms up.
    FRESHNESS_GREEN_HOURS = 30
    FRESHNESS_AMBER_HOURS = 54

    # Top N event bodies surfaced inline; the rest roll up into "other".
    EVENT_BODY_TOP_N = 3

    def initialize(jurisdiction:, now: Time.current)
      @jurisdiction = jurisdiction
      @now = now
    end

    def empty?
      matter_count.zero? && event_count.zero? && attachment_count.zero?
    end

    # --- Freshness -----------------------------------------------------

    def last_synced_at
      @last_synced_at ||= [
        matters.maximum(:last_synced_at),
        events.maximum(:last_synced_at),
        attachments.maximum(:last_synced_at)
      ].compact.max
    end

    def freshness_level
      return :unknown if last_synced_at.nil?

      hours = (@now - last_synced_at) / 1.hour
      return :green if hours <= FRESHNESS_GREEN_HOURS
      return :amber if hours <= FRESHNESS_AMBER_HOURS

      :red
    end

    def matters_synced_since(cutoff)
      matters.where(last_synced_at: cutoff..).count
    end

    def events_synced_since(cutoff)
      events.where(last_synced_at: cutoff..).count
    end

    # --- Breadth -------------------------------------------------------

    def matter_count
      @matter_count ||= matters.count
    end

    def event_count
      @event_count ||= events.current_from_source.count
    end

    def attachment_count
      @attachment_count ||= attachments.current_from_source.count
    end

    def matter_date_range
      return nil if matter_count.zero?

      min, max = matters
        .where.not(agenda_date: nil)
        .pick(Arel.sql("MIN(agenda_date), MAX(agenda_date)"))
      return nil if min.nil? || max.nil?

      min..max
    end

    def most_recent_matter
      matters.where.not(agenda_date: nil).order(agenda_date: :desc).first
    end

    def events_by_body
      counts = events
        .current_from_source
        .where.not(body_name: [ nil, "" ])
        .group(:body_name)
        .count

      sorted = counts.sort_by { |body, count| [ -count, body ] }
      top = sorted.first(EVENT_BODY_TOP_N)
      tail = sorted.drop(EVENT_BODY_TOP_N)

      {
        top: top,
        other_count: tail.sum { |_, count| count },
        other_body_count: tail.size
      }
    end

    # --- Reliability ---------------------------------------------------

    def import_eligible_count
      @import_eligible_count ||= attachments_with_hyperlink.count
    end

    def imported_count
      @imported_count ||= attachments_with_hyperlink.joins(:source_file_attachment).count
    end

    def pdf_imported_count
      @pdf_imported_count ||= imported_pdf_attachments.count
    end

    def pdf_extracted_count
      @pdf_extracted_count ||= imported_pdf_attachments
        .where(id: successful_text_target_ids)
        .count
    end

    def summarizable_count
      @summarizable_count ||= attachments_with_hyperlink
        .where(id: successful_text_target_ids)
        .count
    end

    def summarized_count
      @summarized_count ||= attachments_with_hyperlink
        .where(id: successful_text_target_ids)
        .where(id: current_summary_target_ids)
        .count
    end

    # Matters the theme classifier has processed for the current prompt version.
    # Measured against all matters (not attachments); procedural matters count
    # as classified even though they are intentionally tagged with no themes.
    def theme_classified_count
      @theme_classified_count ||= matters.where(id: current_theme_target_ids).count
    end

    # --- Reconciliation -----------------------------------------------

    def events_removed_since(cutoff)
      events.where(source_present: false, source_missing_at: cutoff..).count
    end

    def attachments_removed_since(cutoff)
      attachments.where(source_present: false, source_missing_at: cutoff..).count
    end

    # --- Caching -------------------------------------------------------

    # Identity changes any time an ingested record in this jurisdiction is
    # written. Suitable for HTTP ETag / fragment caching; clients get 304s
    # until the next write.
    def cache_key
      [
        @jurisdiction.slug,
        cache_component_for(matters),
        cache_component_for(events),
        cache_component_for(attachments),
        cache_component_for(Documents::ExtractedText),
        cache_component_for(Generated::Artifact)
      ].join("/")
    end

    private

    def matters
      Civic::Matter.for_jurisdiction(@jurisdiction)
    end

    def events
      Civic::Event.for_jurisdiction(@jurisdiction)
    end

    def attachments
      Civic::MatterAttachment.for_jurisdiction(@jurisdiction)
    end

    def attachments_with_hyperlink
      attachments
        .current_from_source
        .where.not(hyperlink: [ nil, "" ])
    end

    def imported_pdf_attachments
      attachments_with_hyperlink
        .joins(source_file_attachment: :blob)
        .where(
          "active_storage_blobs.content_type = :pdf OR lower(active_storage_blobs.filename) LIKE :ext",
          pdf: "application/pdf",
          ext: "%.pdf"
        )
    end

    def successful_text_target_ids
      Documents::ExtractedText
        .successful
        .with_content
        .select(:civic_matter_attachment_id)
    end

    def current_summary_target_ids
      Generated::Artifact
        .where(
          target_type: "Civic::MatterAttachment",
          kind: Generated::SummarizeMatterAttachment::KIND,
          prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
          status: "succeeded"
        )
        .select(:target_id)
    end

    def current_theme_target_ids
      Generated::Artifact
        .where(
          target_type: "Civic::Matter",
          kind: Generated::ClassifyMatterThemes::KIND,
          prompt_version: Generated::ClassifyMatterThemes::PROMPT::VERSION,
          status: "succeeded"
        )
        .select(:target_id)
    end

    def cache_component_for(relation)
      [
        relation.count,
        relation.maximum(:updated_at)&.utc&.iso8601(6) || "none"
      ].join(":")
    end
  end
end
