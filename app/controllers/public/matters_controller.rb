module Public
  class MattersController < ApplicationController
    def index
      @query = params[:q].to_s.strip
      @document_matches = document_matches_for(@query)
      document_matter_ids = @document_matches.map { |match| match.matter_attachment.matter.id }.uniq

      scope = Civic::Matter.includes(:attachments)
      scope = scope.where(id: matching_matter_ids(@query, document_matter_ids)) if @query.present?

      @matters = scope.recent_first.limit(50)
      @document_matches_by_matter_id = @document_matches.group_by { |match| match.matter_attachment.matter.id }
    end

    def show
      @matter = Civic::Matter
        .includes(
          event_items: :event,
          attachments: [
            { source_file_attachment: :blob },
            { extracted_texts: [] },
            { generated_artifacts: [] }
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
      metadata_matches = Civic::Matter.search(query)
      return metadata_matches.select(:id) if document_matter_ids.empty?

      metadata_matches.or(Civic::Matter.where(id: document_matter_ids)).select(:id)
    end
  end
end
