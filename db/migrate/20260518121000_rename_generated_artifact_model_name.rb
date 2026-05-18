class RenameGeneratedArtifactModelName < ActiveRecord::Migration[8.1]
  def change
    rename_column :generated_artifacts, :model_name, :model_identifier
    rename_index :generated_artifacts, "idx_generated_artifacts_idempotency", "idx_generated_artifacts_idempotency_old"
    add_index :generated_artifacts,
      [ :target_type, :target_id, :kind, :model_identifier, :prompt_version, :input_sha256 ],
      unique: true,
      name: "idx_generated_artifacts_idempotency"
    remove_index :generated_artifacts, name: "idx_generated_artifacts_idempotency_old"
  end
end
