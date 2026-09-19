require "test_helper"

module Public
  class AboutControllerTest < ActionDispatch::IntegrationTest
    test "explains the project and links to its writing" do
      get about_url

      assert_response :success
      assert_select "title", "About | San Jose Civic Gallery"
      assert_select "body.atlas-shell"
      assert_select "h1", text: /Public records/
      assert_select "a[href=?]", "https://notes.civicgallery.org/", minimum: 1
      assert_select "a[href=?]", "https://notes.civicgallery.org/posts/introducing-civic-gallery/"
      assert_select "a[href=?]", "https://www.davidalexmcclain.com/coding/civic-gallery"
    end

    test "links to notes from the footer and Pulse homepage feature" do
      get root_url

      assert_response :success
      assert_select "section.atlas-notes-feature a[href=?]", "https://notes.civicgallery.org/"
      assert_select "footer a[href=?]", about_path
      assert_select "footer a[href=?]", "https://notes.civicgallery.org/"
    end
  end
end
