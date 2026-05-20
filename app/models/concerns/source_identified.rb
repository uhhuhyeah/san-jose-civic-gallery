# Gives civic records a generic, source-agnostic identity (`source_*_id`)
# scoped by `source_system`, replacing the Legistar-specific id columns as the
# identity of record.
#
# During the Legistar -> generic transition the generic id is derived from the
# legacy Legistar column when not set explicitly, so existing San Jose code
# (which only sets the Legistar id) keeps working unchanged. Once all call
# sites set the generic id directly, the derivation and the legacy columns can
# be removed.
module SourceIdentified
  extend ActiveSupport::Concern

  class_methods do
    def source_identity(generic:, legacy:)
      validates generic, presence: true, uniqueness: { scope: :source_system }

      before_validation do
        self[generic] ||= self[legacy]&.to_s
      end
    end
  end
end
