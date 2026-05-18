class CreateGeneratedArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :generated_artifacts do |t|
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :source_artifact_type
      t.bigint :source_artifact_id
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :model_name, null: false
      t.string :prompt_version, null: false
      t.string :input_sha256, null: false
      t.jsonb :content, null: false, default: {}
      t.jsonb :input_metadata, null: false, default: {}
      t.datetime :generated_at
      t.text :error_message

      t.timestamps
    end

    add_index :generated_artifacts, [ :target_type, :target_id ], name: "idx_generated_artifacts_target"
    add_index :generated_artifacts, [ :source_artifact_type, :source_artifact_id ], name: "idx_generated_artifacts_source"
    add_index :generated_artifacts,
      [ :target_type, :target_id, :kind, :model_name, :prompt_version, :input_sha256 ],
      unique: true,
      name: "idx_generated_artifacts_idempotency"
  end
end
