class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :public_read_only_request?, :current_jurisdiction

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :skip_session_for_public_anonymous_get, if: :public_read_only_request?
  after_action :set_public_cache_headers, if: :public_read_only_request?

  private

  # The jurisdiction whose records this request is scoped to, derived from the
  # request host (sanjose.civicgallery.org -> sanjose, sjusd.civicgallery.org ->
  # sjusd). Unknown hosts (localhost, IP, preview) fall back to the default
  # jurisdiction, so single-host and development behavior is unchanged.
  def current_jurisdiction
    @current_jurisdiction ||=
      Civic::Jurisdiction.find_by(primary_host: request.host) || Civic::Jurisdiction.default
  end

  def public_read_only_request?
    (request.get? || request.head?) && controller_path.start_with?("public/")
  end

  # Prevent Set-Cookie on public anonymous responses so Cloudflare can cache them.
  # Safe because no public action writes to the session or flash, and the search
  # forms submit via GET (no CSRF check). Revisit if a public POST is added.
  def skip_session_for_public_anonymous_get
    request.session_options[:skip] = true
  end

  def set_public_cache_headers
    return unless response.successful? || response.status == 304

    response.headers["Cache-Control"] = "public, max-age=300, s-maxage=7200, stale-while-revalidate=60"
  end
end
