module Civic
  class Jurisdiction < ApplicationRecord
    self.table_name = "civic_jurisdictions"

    KINDS = %w[city school_district county special_district].freeze

    # Canonical jurisdictions. Kept idempotent so seeds.rb and fresh
    # (schema-loaded) databases converge on the same rows. The first
    # SJUSD-introducing migration freezes its own copy of these values.
    DEFAULTS = [
      {
        slug: "sanjose",
        name: "San Jose City Government",
        kind: "city",
        primary_host: "sanjose.civicgallery.org",
        source_system_default: "legistar.sanjose"
      },
      {
        slug: "sjusd",
        name: "San Jose Unified School District",
        kind: "school_district",
        primary_host: "sjusd.civicgallery.org",
        source_system_default: "simbli.sjusd"
      }
    ].freeze

    has_many :events, class_name: "Civic::Event", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception
    has_many :event_items, class_name: "Civic::EventItem", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception
    has_many :matters, class_name: "Civic::Matter", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception
    has_many :matter_attachments, class_name: "Civic::MatterAttachment", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception

    # Slug shape is constrained because views render jurisdiction-specific
    # partials by interpolating the slug into a template path (e.g.
    # `render "public/glossary/#{slug}"`). Path traversal characters or
    # whitespace would either pick the wrong template or raise an unhelpful
    # MissingTemplate. The format below allows only lowercase ASCII, digits,
    # underscores, and hyphens — covers every realistic jurisdiction slug
    # while making the template lookup safe.
    SLUG_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/

    validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT, message: "must be lowercase letters, digits, underscores, or hyphens" }
    validates :name, presence: true
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :primary_host, presence: true, uniqueness: true
    validates :source_system_default, uniqueness: true, allow_nil: true

    def self.for_source_system(source_system)
      return if source_system.blank?

      find_by(source_system_default: source_system)
    end

    def self.default
      find_by(slug: "sanjose")
    end

    def self.seed_defaults!
      DEFAULTS.map do |attributes|
        record = find_or_initialize_by(slug: attributes[:slug])
        record.update!(attributes)
        record
      end
    end

    def to_param
      slug
    end

    # --- Data version -------------------------------------------------------
    # A single timestamp that advances whenever any public-facing record in
    # this jurisdiction changes (see BumpsJurisdictionDataVersion). It is the
    # one freshness input Public::CacheVersion needs, replacing the COUNT/MAX
    # aggregate queries that used to run on every request.

    # Advance the data version. update_all keeps this to one cheap UPDATE with
    # no callbacks and leaves updated_at alone. A nil id bumps every
    # jurisdiction (safe over-invalidation when ownership is unknown).
    def self.bump_data_version!(jurisdiction_id = nil)
      scope = jurisdiction_id ? where(id: jurisdiction_id) : all
      scope.update_all(data_updated_at: Time.current)
    end

    # Opaque component for ETags and cache keys. Reads the attribute as loaded;
    # callers that need to observe a bump made after this record was loaded
    # must reload (controllers are fine: current_jurisdiction is fetched fresh
    # on every request).
    def data_version
      timestamp = data_updated_at || updated_at
      timestamp&.utc&.iso8601(6) || "none"
    end

    # --- Presentation -------------------------------------------------------
    # Jurisdiction-aware copy used across the public UI so a non-default host
    # (e.g. sjusd.civicgallery.org) never reads as San Jose city government.
    # Vocabulary keys off `kind` so future jurisdictions of the same kind work
    # without new branches.

    SHORT_NAMES = {
      "sanjose" => "San Jose",
      "sjusd" => "San Jose Unified School District"
    }.freeze

    SOURCE_HOSTS = {
      "legistar.sanjose" => "sanjose.legistar.com",
      "simbli.sjusd" => "simbli.eboardsolutions.com"
    }.freeze

    SOURCE_LABELS = {
      "legistar.sanjose" => "Legistar",
      "simbli.sjusd" => "Simbli (eBoardSolutions)"
    }.freeze

    # Brand-facing label, shorter than the formal `name`.
    def short_name
      SHORT_NAMES[slug] || name
    end

    # Site/brand title shown in the topbar, page <title>, and metadata.
    def site_title
      "#{short_name} Civic Gallery"
    end

    # Tagline beneath the brand in the topbar.
    def tagline
      city? ? "City Hall agenda intelligence" : "School board agenda intelligence"
    end

    # Default meta description when a page does not set its own.
    def default_description
      "#{site_title} helps residents browse #{records_phrase}, attachments, " \
        "minutes, extracted document text, and official source links."
    end

    # Label for the unfiltered (whole-jurisdiction) scope.
    def all_scope_label
      city? ? "Citywide" : "All bodies"
    end

    # Option label in the body-filter <select>.
    def all_bodies_option_label
      city? ? "All bodies (citywide)" : "All bodies"
    end

    # Link label that returns to the unfiltered view.
    def view_all_scope_label
      city? ? "View Citywide" : "View all bodies"
    end

    # Possessive phrase: "the city's bodies" / "the district's bodies".
    def governing_bodies_phrase
      city? ? "the city's bodies" : "the district's bodies"
    end

    # Subject noun for sentences like "what <subject> is talking about".
    def civic_subject
      city? ? "City Hall" : "the district"
    end

    # Bare jurisdiction noun for editorial copy, e.g. "What the <kind_noun> is
    # paying attention to." Pair with a leading article in the surrounding
    # sentence. Returns lowercase; suitable for mid-sentence use.
    def kind_noun
      city? ? "city" : "district"
    end

    # Public source host this jurisdiction's records are mirrored from.
    def source_host
      SOURCE_HOSTS[source_system_default]
    end

    # Human label for the upstream system records are ingested from.
    def ingestion_source_label
      SOURCE_LABELS[source_system_default]
    end

    def city?
      kind == "city"
    end

    private

    def records_phrase
      if city?
        "#{short_name} City Hall agendas, matters"
      else
        "#{name} board agendas, matters"
      end
    end
  end
end
