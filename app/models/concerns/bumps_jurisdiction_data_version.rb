# Mixed into every model whose rows feed the public pages (civic records,
# extracted document text, generated artifacts). After any committed create,
# update, or destroy, the owning jurisdiction's data version advances so
# Public::CacheVersion ETags and cache keys reflect the new data without
# running per-request COUNT/MAX aggregate queries.
#
# `via:` names an instance method returning the jurisdiction id the record
# belongs to. A nil id bumps every jurisdiction: over-invalidation is the safe
# fallback when ownership cannot be resolved (e.g. a polymorphic target type
# this code does not know about).
module BumpsJurisdictionDataVersion
  extend ActiveSupport::Concern

  class_methods do
    def bumps_jurisdiction_data_version(via: :civic_jurisdiction_id)
      after_commit on: %i[create update destroy] do
        Civic::Jurisdiction.bump_data_version!(send(via))
      end
    end
  end
end
