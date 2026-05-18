require "test_helper"

module Documents
  class RemoteFileProbeTest < ActiveSupport::TestCase
    test "returns metadata from HEAD response" do
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response["Content-Length"] = "450613"
      response["Content-Type"] = "application/pdf"
      response["ETag"] = "\"abc\""
      response["Last-Modified"] = "Fri, 08 May 2026 21:29:53 GMT"

      stub_http_with(response) do |requests|
        result = RemoteFileProbe.call(url: "https://legistar.granicus.com/file.pdf")

        assert_equal :ok, result.status
        assert_equal 450_613, result.content_length
        assert_equal "application/pdf", result.content_type
        assert_equal "\"abc\"", result.etag
        assert_equal Time.httpdate("Fri, 08 May 2026 21:29:53 GMT"), result.last_modified_at
        assert_equal "https://legistar.granicus.com/file.pdf", result.final_url
        assert_equal "HEAD", requests.first.method
      end
    end

    test "sends conditional headers and handles not modified" do
      response = Net::HTTPNotModified.new("1.1", "304", "Not Modified")
      response["ETag"] = "\"abc\""
      timestamp = Time.httpdate("Fri, 08 May 2026 21:29:53 GMT")

      stub_http_with(response) do |requests|
        result = RemoteFileProbe.call(
          url: "https://legistar.granicus.com/file.pdf",
          etag: "\"abc\"",
          last_modified_at: timestamp
        )

        assert result.not_modified?
        assert_equal "\"abc\"", requests.first["If-None-Match"]
        assert_equal timestamp.httpdate, requests.first["If-Modified-Since"]
      end
    end

    test "follows redirects and rejects disallowed hosts" do
      redirect = Net::HTTPFound.new("1.1", "302", "Found")
      redirect["Location"] = "https://evil.example.com/file.pdf"

      stub_http_with(redirect) do
        assert_raises(SafeDownloader::DisallowedHostError) do
          RemoteFileProbe.call(url: "https://sanjose.legistar.com/View.ashx?ID=1")
        end
      end
    end

    private

    def stub_http_with(*responses)
      queue = responses.dup
      requests = []
      original_start = Net::HTTP.method(:start)

      Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |request|
          requests << request
          response = queue.shift
          raise "RemoteFileProbeTest: no more stubbed responses" unless response

          response
        end
        block.call(fake_http)
      end

      yield requests
    ensure
      Net::HTTP.singleton_class.send(:remove_method, :start)
      Net::HTTP.define_singleton_method(:start, original_start)
    end
  end
end
