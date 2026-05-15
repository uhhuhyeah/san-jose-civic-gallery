module ApplicationHelper
  def official_legistar_url(raw_url)
    return if raw_url.blank?

    uri = URI.parse(raw_url)
    return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return unless uri.host.in?(%w[sanjose.legistar.com])

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
