class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :public_read_only_request?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  after_action :set_public_cache_headers, if: :public_read_only_request?

  private

  def public_read_only_request?
    request.get? && controller_path.start_with?("public/")
  end

  def set_public_cache_headers
    return unless response.successful? || response.status == 304

    response.headers["Cache-Control"] = "public, max-age=60, s-maxage=7200, stale-while-revalidate=60"
  end
end
