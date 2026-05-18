module Generated
  class Artifact < ApplicationRecord
    self.table_name = "generated_artifacts"

    STATUSES = %w[pending succeeded failed].freeze

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
  end
end
