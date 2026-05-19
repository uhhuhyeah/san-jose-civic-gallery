require "net/http"
require "uri"

namespace :public do
  desc "Curl representative public routes and print cache-relevant response headers. Set BASE_URL to target a non-local host."
  task cache_smoke: :environment do
    base_url = ENV.fetch("BASE_URL", "http://localhost:3000")
    headers_of_interest = %w[CF-Cache-Status Cache-Control ETag Age Set-Cookie Vary]

    paths = [ "/", "/data", "/public/meetings", "/public/matters" ]
    if (sample_event = Civic::Event.recent_first.first)
      paths << "/public/events/#{sample_event.id}"
    end
    if (sample_matter = Civic::Matter.order(updated_at: :desc).first)
      paths << "/public/matters/#{sample_matter.id}"
    end

    puts "Base: #{base_url}"
    paths.each do |path|
      response = fetch_head(base_url, path)
      puts
      puts "#{response.code} #{path}"
      headers_of_interest.each do |header|
        value = response[header]
        puts "  #{header}: #{value || "(missing)"}"
      end
    rescue StandardError => e
      puts
      puts "ERR #{path}: #{e.class}: #{e.message}"
    end
  end

  def fetch_head(base_url, path)
    uri = URI.join(base_url, path)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri))
    end
  end
end
