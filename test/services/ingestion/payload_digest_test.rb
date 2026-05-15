require "test_helper"

module Ingestion
  class PayloadDigestTest < ActiveSupport::TestCase
    test "hashes equivalent payloads with stable key ordering" do
      a = { "b" => 2, "a" => { "d" => 4, "c" => 3 } }
      b = { "a" => { "c" => 3, "d" => 4 }, "b" => 2 }

      assert_equal PayloadDigest.sha256(a), PayloadDigest.sha256(b)
    end

    test "keeps array order meaningful" do
      assert_not_equal(
        PayloadDigest.sha256([ { "id" => 1 }, { "id" => 2 } ]),
        PayloadDigest.sha256([ { "id" => 2 }, { "id" => 1 } ])
      )
    end
  end
end
