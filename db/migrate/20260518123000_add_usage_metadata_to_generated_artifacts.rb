class AddUsageMetadataToGeneratedArtifacts < ActiveRecord::Migration[8.1]
  def change
    add_column :generated_artifacts, :usage_metadata, :jsonb, null: false, default: {}
  end
end
