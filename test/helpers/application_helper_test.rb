require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "returns the URL for an https://sanjose.legistar.com link" do
    assert_equal "https://sanjose.legistar.com/MeetingDetail.aspx?ID=7621",
      official_legistar_url("https://sanjose.legistar.com/MeetingDetail.aspx?ID=7621")
  end

  test "trims whitespace before validating" do
    assert_equal "https://sanjose.legistar.com/x",
      official_legistar_url("  https://sanjose.legistar.com/x  ")
  end

  test "rejects http URLs" do
    assert_nil official_legistar_url("http://sanjose.legistar.com/x")
  end

  test "rejects URLs on other hosts" do
    assert_nil official_legistar_url("https://evil.example.com/x")
  end

  test "rejects javascript: pseudo-URLs" do
    assert_nil official_legistar_url("javascript:alert(1)")
  end

  test "returns nil for blank or invalid input" do
    assert_nil official_legistar_url(nil)
    assert_nil official_legistar_url("")
    assert_nil official_legistar_url("not a url at all")
  end
end
