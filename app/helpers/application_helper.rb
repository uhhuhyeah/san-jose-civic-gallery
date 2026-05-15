module ApplicationHelper
  OFFICIAL_LEGISTAR_HOST = "sanjose.legistar.com".freeze

  def official_legistar_url(raw_url)
    return if raw_url.blank?

    uri = URI.parse(raw_url.to_s.strip)
    return unless uri.is_a?(URI::HTTPS)
    return unless uri.host == OFFICIAL_LEGISTAR_HOST

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
