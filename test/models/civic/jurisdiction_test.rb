require "test_helper"

module Civic
  class JurisdictionTest < ActiveSupport::TestCase
    test "requires slug, name, kind, primary_host" do
      jurisdiction = Jurisdiction.new

      assert_not jurisdiction.valid?
      assert_includes jurisdiction.errors[:slug], "can't be blank"
      assert_includes jurisdiction.errors[:name], "can't be blank"
      assert_includes jurisdiction.errors[:kind], "can't be blank"
      assert_includes jurisdiction.errors[:primary_host], "can't be blank"
    end

    test "slug and primary_host are unique and kind is constrained" do
      duplicate = Jurisdiction.new(
        slug: "sanjose",
        name: "Dup",
        kind: "city",
        primary_host: "sanjose.civicgallery.org"
      )

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:slug], "has already been taken"
      assert_includes duplicate.errors[:primary_host], "has already been taken"

      bad_kind = Jurisdiction.new(slug: "x", name: "X", kind: "borough", primary_host: "x.example.com")
      assert_not bad_kind.valid?
      assert_includes bad_kind.errors[:kind], "is not included in the list"
    end

    test "for_source_system maps a source system to its jurisdiction" do
      assert_equal civic_jurisdictions(:sanjose), Jurisdiction.for_source_system("legistar.sanjose")
      assert_equal civic_jurisdictions(:sjusd), Jurisdiction.for_source_system("simbli.sjusd")
      assert_nil Jurisdiction.for_source_system("unknown.source")
      assert_nil Jurisdiction.for_source_system(nil)
    end

    test "seed_defaults! is idempotent and converges attributes" do
      assert_no_difference -> { Jurisdiction.count } do
        Jurisdiction.seed_defaults!
      end

      assert_equal "school_district", civic_jurisdictions(:sjusd).reload.kind
    end

    test "civic records derive their jurisdiction from source_system when unset" do
      event = Event.create!(legistar_event_id: 91001, event_date: Date.new(2026, 5, 1))
      assert_equal civic_jurisdictions(:sanjose), event.civic_jurisdiction

      sjusd_event = Event.create!(
        legistar_event_id: 91002,
        event_date: Date.new(2026, 5, 1),
        source_system: "simbli.sjusd"
      )
      assert_equal civic_jurisdictions(:sjusd), sjusd_event.civic_jurisdiction
    end

    test "presentation copy is city-specific for the city jurisdiction" do
      sanjose = civic_jurisdictions(:sanjose)

      assert_equal "San Jose", sanjose.short_name
      assert_equal "San Jose Civic Gallery", sanjose.site_title
      assert_equal "City Hall agenda intelligence", sanjose.tagline
      assert_equal "Citywide", sanjose.all_scope_label
      assert_equal "All bodies (citywide)", sanjose.all_bodies_option_label
      assert_equal "View Citywide", sanjose.view_all_scope_label
      assert_equal "the city's bodies", sanjose.governing_bodies_phrase
      assert_equal "City Hall", sanjose.civic_subject
      assert_equal "sanjose.legistar.com", sanjose.source_host
      assert_includes sanjose.default_description, "San Jose City Hall agendas"
    end

    test "presentation copy is district-specific for a school district" do
      sjusd = civic_jurisdictions(:sjusd)

      assert_equal "San Jose Unified", sjusd.short_name
      assert_equal "San Jose Unified Civic Gallery", sjusd.site_title
      assert_equal "School board agenda intelligence", sjusd.tagline
      assert_equal "All bodies", sjusd.all_scope_label
      assert_equal "All bodies", sjusd.all_bodies_option_label
      assert_equal "View all bodies", sjusd.view_all_scope_label
      assert_equal "the district's bodies", sjusd.governing_bodies_phrase
      assert_equal "the district", sjusd.civic_subject
      assert_equal "simbli.eboardsolutions.com", sjusd.source_host
      assert_includes sjusd.default_description, "San Jose Unified School District board agendas"
      assert_not_includes sjusd.default_description, "City Hall"
    end

    test "for_jurisdiction scopes civic records to a single jurisdiction" do
      sanjose_event = Event.create!(legistar_event_id: 91003, event_date: Date.new(2026, 5, 1))
      sjusd_event = Event.create!(
        legistar_event_id: 91004,
        event_date: Date.new(2026, 5, 1),
        source_system: "simbli.sjusd"
      )

      scoped = Event.for_jurisdiction(civic_jurisdictions(:sanjose))
      assert_includes scoped, sanjose_event
      assert_not_includes scoped, sjusd_event
    end
  end
end
