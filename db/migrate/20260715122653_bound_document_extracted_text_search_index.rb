class BoundDocumentExtractedTextSearchIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  SEARCH_INDEX_CHARACTER_LIMIT = 200_000

  def up
    remove_index :document_extracted_texts,
      name: "idx_document_extracted_texts_content_search",
      algorithm: :concurrently,
      if_exists: true

    add_index :document_extracted_texts,
      "to_tsvector('english', left(coalesce(content, ''), #{SEARCH_INDEX_CHARACTER_LIMIT}))",
      using: :gin,
      where: "status = 'ok'",
      name: "idx_document_extracted_texts_content_search",
      algorithm: :concurrently
  end

  def down
    remove_index :document_extracted_texts,
      name: "idx_document_extracted_texts_content_search",
      algorithm: :concurrently,
      if_exists: true

    add_index :document_extracted_texts,
      "to_tsvector('english', coalesce(content, ''))",
      using: :gin,
      where: "status = 'ok'",
      name: "idx_document_extracted_texts_content_search",
      algorithm: :concurrently
  end
end
