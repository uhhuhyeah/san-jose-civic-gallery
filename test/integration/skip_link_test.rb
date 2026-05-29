require "test_helper"

# Asserts the skip-to-main-content link is present on every public page and
# that each page has a corresponding `id="main"` target. The link is rendered
# globally from `app/views/layouts/application.html.erb` and styled by
# `app/assets/stylesheets/application.css` (so it works on Atlas and
# pre-Atlas pages alike). If this test fails, keyboard and screen-reader
# users can't skip the topbar — covers a regression class that would
# otherwise be silent.
class SkipLinkTest < ActionDispatch::IntegrationTest
  SANJOSE_HOST = "sanjose.civicgallery.org".freeze

  setup do
    Civic::Jurisdiction.seed_defaults!
    host! SANJOSE_HOST
  end

  test "Atlas pulse homepage exposes a skip link pointing at #main" do
    get root_path

    assert_response :success
    assert_skip_link_present
    assert_main_target_present
  end

  test "Atlas matters index exposes a skip link pointing at #main" do
    get public_matters_path

    assert_response :success
    assert_skip_link_present
    assert_main_target_present
  end

  test "Atlas glossary exposes a skip link pointing at #main" do
    get glossary_path

    assert_response :success
    assert_skip_link_present
    assert_main_target_present
  end

  test "Atlas data health page exposes a skip link pointing at #main" do
    get data_path

    assert_response :success
    assert_skip_link_present
    assert_main_target_present
  end

  test "Atlas meetings index exposes a skip link pointing at #main" do
    get "/public/meetings"

    assert_response :success
    assert_skip_link_present
    assert_main_target_present
  end

  test "non-Atlas roundups index exposes a skip link pointing at #main" do
    # Roundups still use `page-shell`, not Atlas. Verifies the skip link
    # works outside Atlas — the bug we're guarding against would only
    # manifest on this page.
    get roundups_path

    assert_response :success
    assert_skip_link_present
    assert_main_target_present
  end

  test "skip link appears before any topbar nav link in source order" do
    # Source order matters: keyboard users need the skip link as the very
    # first focusable element so a single Tab reveals it before the nav.
    get root_path

    body = response.body
    skip_index = body.index('class="atlas-skip-link"')
    nav_index  = body.index("<nav")
    refute_nil skip_index, "expected skip link in response body"
    refute_nil nav_index,  "expected a <nav> in response body"
    assert skip_index < nav_index,
           "skip link must appear before nav in source order"
  end

  private

  def assert_skip_link_present
    assert_select "a.atlas-skip-link[href='#main']", count: 1,
                  message: "expected one skip-to-main-content link"
  end

  def assert_main_target_present
    assert_select "#main", count: 1,
                  message: "expected exactly one element with id='main' as the skip-link target"
  end
end
