module SearchableText
  extend ActiveSupport::Concern

  included do
    after_save :persist_searchable_text!, if: :should_persist_searchable_text?
  end

  # Override in each model to return the concatenated text
  def compute_searchable_text
    raise NotImplementedError
  end

  # Override in each model to return array of column names that affect the text
  def searchable_text_watched_columns
    []
  end

  # Called as public method from sync services to force recompute (e.g. when child records change)
  def update_searchable_text!
    self.class.where(id: id).update_all(searchable_text: compute_searchable_text)
  end

  private

  def persist_searchable_text!
    self.class.where(id: id).update_all(searchable_text: compute_searchable_text)
  end

  def should_persist_searchable_text?
    (saved_changes.keys.map(&:to_s) & searchable_text_watched_columns).any?
  end
end
