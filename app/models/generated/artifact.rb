module Generated
  class Artifact < ApplicationRecord
    self.table_name = "generated_artifacts"

    STATUSES = %w[pending succeeded failed].freeze

    include BumpsJurisdictionDataVersion

    bumps_jurisdiction_data_version via: :jurisdiction_id_for_data_version

    belongs_to :target, polymorphic: true
    belongs_to :source_artifact, polymorphic: true, optional: true

    validates :target, presence: true
    validates :kind, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :model_identifier, presence: true
    validates :prompt_version, presence: true
    validates :input_sha256, presence: true

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :succeeded, -> { where(status: "succeeded") }
    scope :for_kind, ->(kind) { where(kind:) }

    private

    # Targets are events, matters, attachments, or roundup periods, all of
    # which carry civic_jurisdiction_id. An unknown target type returns nil,
    # which bumps every jurisdiction rather than missing an invalidation.
    def jurisdiction_id_for_data_version
      target.try(:civic_jurisdiction_id)
    end
  end
end
