module PublicRateLimitedSearch
  extend ActiveSupport::Concern

  # Generous public-records limit: 60 search requests per minute per IP per
  # search endpoint. Broad access is the point of a public-records site; this
  # only guards against a dumb scraper saturating Postgres with ILIKE joins
  # that bypass the edge cache. Non-search browsing is never throttled.
  SEARCH_RATE_LIMIT = 60
  SEARCH_RATE_WINDOW = 1.minute

  # Dedicated store so rate-limit counters are isolated from app cache: a
  # Solid Cache flush or cache eviction must not reset throttles, and counter
  # writes must not evict cached pages. MemoryStore is per-process, which is
  # correct for the single-Puma-process deployment model.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  included do
    rate_limit to: SEARCH_RATE_LIMIT,
               within: SEARCH_RATE_WINDOW,
               only: :index,
               if: :search_query?,
               by: :rate_limit_identity,
               with: :log_search_rate_limit_exceeded,
               store: RATE_LIMIT_STORE
  end

  private

  def search_query?
    params[:q].to_s.strip.present?
  end

  # Cloudflare-aware identity. Production currently terminates TLS at
  # Cloudflare and forwards to the app over a private network, so Rails sees
  # Cloudflare's edge IP as REMOTE_ADDR (e.g. 104.22.20.83) and
  # trusted_proxies is unset. Keying by request.remote_ip would put every
  # real visitor behind one shared edge-IP bucket and let a single scraper
  # exhaust everyone's 60/minute quota. CF-Connecting-IP is the header
  # Cloudflare sets with the true client IP, so prefer it when present and
  # fall back to remote_ip for local/dev or non-Cloudflare deployments.
  def rate_limit_identity
    request.get_header("HTTP_CF_CONNECTING_IP").presence || request.remote_ip
  end

  def log_search_rate_limit_exceeded
    identity = rate_limit_identity
    edge_ip = request.remote_ip
    Rails.logger.warn(
      "[rate-limit] identity=#{identity} edge_remote_ip=#{edge_ip} " \
      "exceeded #{SEARCH_RATE_LIMIT} search requests per " \
      "#{SEARCH_RATE_WINDOW.inspect} on #{controller_path}##{action_name}"
    )
    raise ActionController::TooManyRequests
  end
end
