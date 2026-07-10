class CreateSearchEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :search_embeddings do |t|
      t.references :civic_jurisdiction, null: false, foreign_key: true
      t.string :source_record_type, null: false
      t.bigint :source_record_id, null: false
      t.string :result_record_type, null: false
      t.bigint :result_record_id, null: false
      t.string :source_kind, null: false
      t.integer :chunk_index
      t.string :content_sha256, null: false
      t.string :embedding_model, null: false
      t.integer :embedding_dimensions, null: false
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, null: false, default: {}
      t.datetime :embedded_at

      t.timestamps
    end

    add_index :search_embeddings, :civic_jurisdiction_id, name: "idx_search_embeddings_jurisdiction"
    add_index :search_embeddings, [ :source_record_type, :source_record_id ], name: "idx_search_embeddings_source"
    add_index :search_embeddings, [ :result_record_type, :result_record_id ], name: "idx_search_embeddings_result"
    add_index :search_embeddings,
      [ :source_record_type, :source_record_id, :source_kind, :chunk_index, :embedding_model, :content_sha256 ],
      unique: true,
      name: "idx_search_embeddings_idempotency"
  end
end
