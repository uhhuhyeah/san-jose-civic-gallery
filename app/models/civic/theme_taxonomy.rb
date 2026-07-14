module Civic
  # Per-jurisdiction closed vocabularies of civic themes used to tag matters for
  # the Pulse discovery feature. Each list is intentionally broad so appearance
  # counts aggregate into real signal instead of fragmenting across near-synonyms.
  #
  # Vocabularies are per-jurisdiction by design: a city government and a school
  # district frame their work around different topics. Slugs are scoped to a
  # jurisdiction (validated by Civic::MatterTheme against the matter's
  # jurisdiction), so the same slug may appear in more than one list without
  # collision.
  #
  # Editing a list is a breaking change for that jurisdiction's generated theme
  # tags: bump the corresponding prompt VERSION (see
  # Generated::ClassifyMatterThemes::PROMPTS_BY_JURISDICTION) so the backfill
  # re-tags that jurisdiction's matters against the new vocabulary. Because the
  # prompt version is part of the artifact idempotency key and is resolved per
  # jurisdiction, editing one jurisdiction's taxonomy never re-tags another's.
  # Slugs are the stable identifier stored in civic_matter_themes; labels are
  # display-only and safe to reword without a re-tag.
  module ThemeTaxonomy
    SANJOSE = [
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

    SJUSD = [
      { slug: "curriculum_instruction", label: "Curriculum & Instruction" },
      { slug: "academic_outcomes", label: "Academic Outcomes & Assessment" },
      { slug: "special_education", label: "Special Education" },
      { slug: "student_wellness", label: "Student Health & Wellness" },
      { slug: "school_safety", label: "School Safety & Climate" },
      { slug: "enrollment_boundaries", label: "Enrollment & Boundaries" },
      { slug: "facilities_bonds", label: "Facilities & Bonds" },
      { slug: "budget_finance", label: "Budget & Finance" },
      { slug: "labor_personnel", label: "Labor & Personnel" },
      { slug: "governance_policy", label: "Governance & Board Policy" },
      { slug: "equity_inclusion", label: "Equity & Inclusion" },
      { slug: "technology", label: "Technology" },
      { slug: "transportation", label: "Transportation" },
      { slug: "family_community", label: "Family & Community Engagement" },
      { slug: "legal_litigation", label: "Legal & Litigation" },
      { slug: "contracts_procurement", label: "Contracts & Procurement" }
    ].freeze

    SANTACLARA = [
      { slug: "health_hospital", label: "Health & Hospital System" },
      { slug: "social_services", label: "Social Services & Safety Net" },
      { slug: "housing", label: "Housing" },
      { slug: "homelessness", label: "Homelessness" },
      { slug: "public_safety_justice", label: "Public Safety & Criminal Justice" },
      { slug: "land_use_planning", label: "Land Use & Planning" },
      { slug: "transportation_roads", label: "Transportation & Roads" },
      { slug: "environment_sustainability", label: "Environment & Sustainability" },
      { slug: "parks_recreation", label: "Parks & Recreation" },
      { slug: "budget_finance", label: "Budget & Finance" },
      { slug: "elections_governance", label: "Elections & Governance" },
      { slug: "assessment_taxation", label: "Assessment & Property Tax" },
      { slug: "children_families_seniors", label: "Children, Families & Seniors" },
      { slug: "labor_employment", label: "Labor & Employment" },
      { slug: "legal_litigation", label: "Legal & Litigation" },
      { slug: "contracts_procurement", label: "Contracts & Procurement" },
      { slug: "technology", label: "Technology & Data" },
      { slug: "equity_immigration", label: "Equity & Immigrant Affairs" }
    ].freeze

    BY_JURISDICTION_SLUG = {
      "sanjose" => SANJOSE,
      "sjusd" => SJUSD,
      "santaclaracounty" => SANTACLARA
    }.freeze

    # Unknown or nil jurisdictions fall back to the city vocabulary, matching the
    # default jurisdiction used elsewhere for unresolved hosts.
    DEFAULT = SANJOSE

    module_function

    # Accepts a Civic::Jurisdiction (or its slug string, or nil) and returns the
    # theme list for it.
    def themes_for(jurisdiction)
      slug = jurisdiction.respond_to?(:slug) ? jurisdiction.slug : jurisdiction
      BY_JURISDICTION_SLUG.fetch(slug, DEFAULT)
    end

    def slugs_for(jurisdiction)
      themes_for(jurisdiction).map { |theme| theme[:slug] }
    end

    def valid_slug?(slug, jurisdiction)
      themes_for(jurisdiction).any? { |theme| theme[:slug] == slug }
    end

    def label_for(slug, jurisdiction)
      themes_for(jurisdiction).find { |theme| theme[:slug] == slug }&.dig(:label)
    end
  end
end
