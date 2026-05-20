module Civic
  # Closed vocabulary of civic themes used to tag matters for the Pulse
  # discovery feature. The list is intentionally broad so appearance counts
  # aggregate into real signal instead of fragmenting across near-synonyms.
  #
  # Editing this list is a breaking change for generated theme tags: bump
  # Generated::Prompts::MatterThemesV1::VERSION so the backfill re-tags every
  # matter against the new vocabulary. Slugs are the stable identifier stored
  # in civic_matter_themes; labels are display-only and safe to reword without
  # a re-tag.
  module ThemeTaxonomy
    THEMES = [
      { slug: "housing", label: "Housing" },
      { slug: "land_use_zoning", label: "Land Use & Zoning" },
      { slug: "transportation", label: "Transportation" },
      { slug: "public_safety", label: "Public Safety" },
      { slug: "parks_recreation", label: "Parks & Recreation" },
      { slug: "budget_finance", label: "Budget & Finance" },
      { slug: "environment_sustainability", label: "Environment & Sustainability" },
      { slug: "economic_development", label: "Economic Development" },
      { slug: "homelessness", label: "Homelessness" },
      { slug: "infrastructure_public_works", label: "Infrastructure & Public Works" },
      { slug: "health_human_services", label: "Health & Human Services" },
      { slug: "arts_culture", label: "Arts & Culture" },
      { slug: "governance_elections", label: "Governance & Elections" },
      { slug: "legal_litigation", label: "Legal & Litigation" },
      { slug: "utilities", label: "Utilities" },
      { slug: "public_records_transparency", label: "Public Records & Transparency" },
      { slug: "labor_employment", label: "Labor & Employment" }
    ].freeze

    SLUGS = THEMES.map { |theme| theme[:slug] }.freeze
    LABELS_BY_SLUG = THEMES.to_h { |theme| [ theme[:slug], theme[:label] ] }.freeze

    module_function

    def slugs
      SLUGS
    end

    def valid_slug?(slug)
      LABELS_BY_SLUG.key?(slug)
    end

    def label_for(slug)
      LABELS_BY_SLUG[slug]
    end
  end
end
