module Public
  # Defines the parameter values accepted by durable landing-page show actions.
  # Discovery uses the same predicates so it never advertises a URL that its
  # corresponding controller would reject.
  module LandingPageEligibility
    MIN_YEAR = 2000

    module_function

    def topic_slug?(slug, jurisdiction)
      Civic::ThemeTaxonomy.valid_slug?(slug, jurisdiction)
    end

    def body_scope(jurisdiction)
      Civic::Event
        .current_from_source
        .for_jurisdiction(jurisdiction)
        .where.not(body_name: [ nil, "" ])
    end

    def body_names(jurisdiction)
      body_scope(jurisdiction).distinct.order(:body_name).pluck(:body_name)
    end

    def valid_year?(year)
      year.to_i.between?(MIN_YEAR, Date.current.year + 1)
    end
  end
end
