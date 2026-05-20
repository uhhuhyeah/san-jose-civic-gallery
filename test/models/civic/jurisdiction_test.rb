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
