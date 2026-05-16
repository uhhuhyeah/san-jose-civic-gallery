class AddFullTextIndexToDocumentExtractedTexts < ActiveRecord::Migration[8.1]
  def change
    add_index :document_extracted_texts,
      "to_tsvector('english', coalesce(content, ''))",
      using: :gin,
      where: "status = 'ok'",
      name: "idx_document_extracted_texts_content_search"
  end
end
