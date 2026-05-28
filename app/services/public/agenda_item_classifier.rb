module Public
  # Tags each `Civic::EventItem` on a meeting agenda as one of three tiers:
  #
  #   - :substantive — has a `civic_matter_id` (a real matter being heard)
  #   - :section     — an agenda scope marker like (a), (b), (c), (d), or •
  #   - :notice      — boilerplate / participation / legal notices (everything else)
  #
  # The decision tree is deterministic from columns already on civic_event_items.
  # No ML needed. See docs/redesign-data-spike.md section 5.
  #
  # Substantive ratio on production (2026-05-28): ~27.7% of event items carry a
  # civic_matter_id. A representative meeting sample should land in 25-30%; a
  # body shape that lands wildly outside that range usually means the source
  # data uses a marker pattern the classifier doesn't recognize.
  module AgendaItemClassifier
    # An agenda_number is a section marker when it matches "(a)" through "(z)"
    # or a bullet "•". Substantive items use digit markers like "1." or "3.4".
    SECTION_PATTERN = /\A\s*(?:\([a-z]\)|•)\s*\z/

    # Returns :substantive | :section | :notice for a single EventItem.
    #
    # `matter_id` is the upstream Legistar foreign id; `civic_matter_id` is the
    # local FK after sync. An item with either is meant to be substantive — if
    # only `matter_id` is present, the matter sync is pending and the view
    # surfaces that state inline.
    def self.classify(item)
      return :substantive if item.civic_matter_id.present? || item.matter_id.present?
      return :section     if item.agenda_number.to_s.match?(SECTION_PATTERN)

      :notice
    end

    # Convenience: returns an array of [kind, item] pairs in the same order as
    # the input. Lets the view iterate in agenda order while branching on kind.
    def self.tag(items)
      items.map { |item| [ classify(item), item ] }
    end
  end
end
