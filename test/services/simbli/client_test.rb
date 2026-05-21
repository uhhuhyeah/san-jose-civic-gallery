require "test_helper"

module Simbli
  class ClientTest < ActiveSupport::TestCase
    setup do
      @agenda = JSON.parse(file_fixture("simbli/agenda_tree.json").read)
      @docs = JSON.parse(file_fixture("simbli/supporting_documents.json").read)
    end

    test "agenda_tree returns the agenda payload in the sync contract shape" do
      result = client(meeting_json).agenda_tree(mid: "57394")

      assert_equal @agenda, result[:payload]
      assert_equal 200, result[:status]
      assert result[:response_sha256].present?
      assert_includes result[:request_url], "MID=57394"
    end

    test "supporting_documents returns docs for a known agenda id, empty otherwise" do
      client = client(meeting_json)

      assert_equal 2, client.supporting_documents(mid: "57394", agenda_id: 201)[:payload]["Attachment"].size
      assert_empty client.supporting_documents(mid: "57394", agenda_id: 999)[:payload]["Attachment"]
    end

    test "raises BlockedError on an anti-bot interstitial" do
      blocked = client({ "blocked" => true, "blockedBy" => "Incapsula incident" }.to_json)

      assert_raises(Client::BlockedError) { blocked.agenda_tree(mid: "57394") }
    end

    test "raises FetchError on a non-zero exit" do
      failing = client("", stderr: "boom", success: false)

      assert_raises(Client::FetchError) { failing.agenda_tree(mid: "57394") }
    end

    test "fetches each meeting only once and serves both methods from cache" do
      calls = 0
      capture = lambda do |_args|
        calls += 1
        [ meeting_json, "", FakeStatus.new(true, 0) ]
      end

      instance = Client.new(capture: capture)
      instance.agenda_tree(mid: "57394")
      instance.supporting_documents(mid: "57394", agenda_id: 201)

      assert_equal 1, calls
    end

    test "meeting_listing returns the listing rows in the contract shape" do
      rows = [ { "onclick" => "ViewMeeting(\"36030421\",\"57394\")", "cells" => {} } ]
      listing = Client.new(capture: ->(_args) { [ { "ok" => true, "rows" => rows }.to_json, "", FakeStatus.new(true, 0) ] })

      result = listing.meeting_listing
      assert_equal rows, result[:payload]
      assert_includes result[:request_url], "SB_MeetingListing.aspx"
    end

    private

    FakeStatus = Struct.new(:ok, :exitstatus) do
      def success?
        ok
      end
    end

    def meeting_json
      { "ok" => true, "blocked" => false, "agenda" => @agenda, "supportingDocuments" => { "201" => @docs } }.to_json
    end

    def client(stdout, stderr: "", success: true)
      Client.new(capture: ->(_args) { [ stdout, stderr, FakeStatus.new(success, success ? 0 : 1) ] })
    end
  end
end
