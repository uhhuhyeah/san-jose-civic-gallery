module Public
  class MattersController < ApplicationController
    def index
      @query = params[:q].to_s.strip
      @document_matches = document_matches_for(@query)
      document_matter_ids = @document_matches.map { |match| match.matter_attachment.matter.id }
      @matters = Civic::Matter
        .includes(:attachments)
        .where(id: matching_matter_ids(@query, document_matter_ids))
        .recent_first
        .limit(50)
      @document_matches_by_matter_id = @document_matches.group_by { |match| match.matter_attachment.matter.id }
    end

    def show
      @matter = Civic::Matter
        .includes(
          event_items: :event,
          attachments: [
            { source_file_attachment: :blob },
            { extracted_texts: [] }
          ]
        )
        .find(params[:id])
      @event_items = @matter.event_items.agenda_order.includes(:event)
    end

    private

    def document_matches_for(query)
      return [] if query.blank?

      Documents::ExtractedText
        .search(query)
        .joins(matter_attachment: :matter)
        .merge(Civic::MatterAttachment.current_from_source)
        .includes(matter_attachment: :matter)
        .limit(20)
        .to_a
    end

    def matching_matter_ids(query, document_matter_ids)
      metadata_match_ids = Civic::Matter.search(query).select(:id)
      return metadata_match_ids if document_matter_ids.empty?

      Civic::Matter.where(id: metadata_match_ids).or(Civic::Matter.where(id: document_matter_ids)).select(:id)
    end
  end
end
