require "digest"

module Documents
  # Single source of truth for the official civic-record hosts we trust.
  #
  # ATTACHMENT_HOSTS are the hosts SafeHttpClient may fetch attachment files
  # from (overridable via LEGISTAR_ATTACHMENT_ALLOWED_HOSTS). LINK_ONLY_HOSTS
  # are official sources we link to but never fetch through SafeHttpClient.
  # LINK_HOSTS is everything the public UI and APIs may render as an
  # "official source" link, so every fetchable host is also linkable.
  module OfficialSourceHosts
    ATTACHMENT_HOSTS = %w[
      sanjose.legistar.com
      scvwd.legistar.com
      legistar.granicus.com
      www.sanjoseca.gov
      sccgov.iqm2.com
    ].freeze

    LINK_ONLY_HOSTS = %w[
      simbli.eboardsolutions.com
    ].freeze

    LINK_HOSTS = (ATTACHMENT_HOSTS + LINK_ONLY_HOSTS).freeze

    # Short fingerprint of a host list. Fragment caches that render official
    # source links fold this in, because their record-based keys do not change
    # when a host is added and would otherwise keep serving "unavailable".
    def self.digest(hosts = LINK_HOSTS)
      Digest::SHA256.hexdigest(hosts.sort.join(",")).first(12)
    end
  end
end
