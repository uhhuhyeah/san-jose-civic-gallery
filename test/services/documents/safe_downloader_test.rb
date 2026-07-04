require "test_helper"
require "stringio"

module Documents
  class SafeDownloaderTest < ActiveSupport::TestCase
    test "rejects URLs whose host is not in the allowlist" do
      io = StringIO.new

      error = assert_raises(SafeDownloader::DisallowedHostError) do
        SafeDownloader.call(url: "https://evil.example.com/file.pdf", io:)
      end

      assert_match(/evil\.example\.com/, error.message)
    end

    test "rejects http URLs by default" do
      io = StringIO.new

      assert_raises(SafeDownloader::DisallowedSchemeError) do
        SafeDownloader.call(url: "http://sanjose.legistar.com/file.pdf", io:)
      end
    end

    test "rejects file:// and other non-http schemes" do
      io = StringIO.new

      assert_raises(SafeDownloader::DisallowedSchemeError) do
        SafeDownloader.call(url: "file:///etc/passwd", io:)
      end
    end

    test "raises on invalid URLs" do
      io = StringIO.new

      assert_raises(SafeDownloader::Error) do
        SafeDownloader.call(url: "not a url at all", io:)
      end
    end

    test "streams body to io, computes sha256, returns byte size and content type" do
      body = "%PDF-1.4 fake pdf body"

      stub_http_with(SafeDownloaderTest.fake_success(
        headers: {
          "Content-Type" => "application/pdf",
          "ETag" => "\"abc\"",
          "Last-Modified" => "Fri, 08 May 2026 21:29:53 GMT"
        },
        chunks: [ body ]
      )) do
        io = StringIO.new
        result = SafeDownloader.call(url: "https://sanjose.legistar.com/file.pdf", io:)

        assert_equal body, io.string
        assert_equal body.bytesize, result.byte_size
        assert_equal "application/pdf", result.content_type
        assert_equal Digest::SHA256.hexdigest(body), result.checksum_sha256
        assert_equal "\"abc\"", result.etag
        assert_equal Time.httpdate("Fri, 08 May 2026 21:29:53 GMT"), result.last_modified_at
      end
    end

    test "follows redirects up to the cap, re-validating the host each hop" do
      first = SafeDownloaderTest.fake_redirect(location: "https://sanjose.legistar.com/file.pdf")
      success = SafeDownloaderTest.fake_success(
        headers: { "Content-Type" => "application/pdf" },
        chunks: [ "%PDF-1.4 ok" ]
      )

      stub_http_with(first, success) do
        io = StringIO.new
        result = SafeDownloader.call(url: "https://sanjose.legistar.com/View.ashx?M=F&ID=1", io:)

        assert_equal "%PDF-1.4 ok", io.string
        assert_equal "https://sanjose.legistar.com/file.pdf", result.final_url
      end
    end

    test "rejects redirects to a disallowed host" do
      redirect = SafeDownloaderTest.fake_redirect(location: "https://evil.example.com/file.pdf")

      stub_http_with(redirect) do
        io = StringIO.new
        assert_raises(SafeDownloader::DisallowedHostError) do
          SafeDownloader.call(url: "https://sanjose.legistar.com/View.ashx?M=F&ID=1", io:)
        end
      end
    end

    test "rejects responses whose Content-Length exceeds the cap" do
      huge = SafeDownloaderTest.fake_success(
        headers: { "Content-Type" => "application/pdf", "Content-Length" => (200 * 1024 * 1024).to_s },
        chunks: [ "irrelevant" ]
      )

      stub_http_with(huge) do
        io = StringIO.new
        assert_raises(SafeDownloader::TooLargeError) do
          SafeDownloader.call(url: "https://sanjose.legistar.com/file.pdf", io:)
        end
      end
    end

    test "rejects mid-stream when the byte count exceeds the cap" do
      ENV["LEGISTAR_ATTACHMENT_MAX_BYTES"] = "10"

      streaming = SafeDownloaderTest.fake_success(
        headers: { "Content-Type" => "application/pdf" },
        chunks: [ "abcd", "efgh", "ijklmnop" ]
      )

      stub_http_with(streaming) do
        io = StringIO.new
        assert_raises(SafeDownloader::TooLargeError) do
          SafeDownloader.call(url: "https://sanjose.legistar.com/file.pdf", io:)
        end
      end
    ensure
      ENV.delete("LEGISTAR_ATTACHMENT_MAX_BYTES")
    end

    test "raises HttpError on non-2xx non-3xx responses" do
      stub_http_with(SafeDownloaderTest.fake_server_error) do
        io = StringIO.new
        assert_raises(SafeDownloader::HttpError) do
          SafeDownloader.call(url: "https://sanjose.legistar.com/file.pdf", io:)
        end
      end
    end

    test "raises HttpServerError (the retried subclass) for 5xx responses" do
      stub_http_with(SafeDownloaderTest.fake_server_error) do
        io = StringIO.new
        error = assert_raises(SafeHttpClient::HttpServerError) do
          SafeDownloader.call(url: "https://sanjose.legistar.com/file.pdf", io:)
        end
        assert_kind_of SafeHttpClient::HttpError, error
        assert_equal 500, error.status
      end
    end

    test "raises plain HttpError (not the retried 5xx subclass) for 4xx responses" do
      stub_http_with(SafeDownloaderTest.fake_client_error) do
        io = StringIO.new
        error = assert_raises(SafeDownloader::HttpError) do
          SafeDownloader.call(url: "https://sanjose.legistar.com/file.pdf", io:)
        end
        assert_not_kind_of SafeHttpClient::HttpServerError, error
        assert_equal 403, error.status
      end
    end

    test "respects LEGISTAR_ATTACHMENT_ALLOWED_HOSTS env var" do
      ENV["LEGISTAR_ATTACHMENT_ALLOWED_HOSTS"] = "other.example.com,extra.example.com"

      stub_http_with(SafeDownloaderTest.fake_success(headers: {}, chunks: [ "body" ])) do
        io = StringIO.new
        SafeDownloader.call(url: "https://other.example.com/x.pdf", io:)

        assert_equal "body", io.string
      end
    ensure
      ENV.delete("LEGISTAR_ATTACHMENT_ALLOWED_HOSTS")
    end

    test "allows direct granicus attachment host by default" do
      stub_http_with(SafeDownloaderTest.fake_success(headers: {}, chunks: [ "body" ])) do
        io = StringIO.new
        SafeDownloader.call(url: "https://legistar.granicus.com/sanjose/attachments/file.pdf", io:)

        assert_equal "body", io.string
      end
    end

    def self.fake_success(headers:, chunks:)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      headers.each { |k, v| response[k] = v }
      response.instance_variable_set(:@__chunks, chunks)
      response.define_singleton_method(:read_body) do |&block|
        @__chunks.each { |chunk| block.call(chunk) }
      end
      response
    end

    def self.fake_redirect(location:)
      response = Net::HTTPFound.new("1.1", "302", "Found")
      response["Location"] = location
      response.define_singleton_method(:read_body) { |&_block| }
      response
    end

    def self.fake_server_error
      response = Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error")
      response.define_singleton_method(:read_body) { |&_block| }
      response
    end

    def self.fake_client_error
      response = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
      response.define_singleton_method(:read_body) { |&_block| }
      response
    end

    private

    def stub_http_with(*responses)
      queue = responses.dup
      original_start = Net::HTTP.method(:start)

      Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |_req, &response_block|
          response = queue.shift
          raise "SafeDownloaderTest: no more stubbed responses" unless response

          response_block.call(response)
        end
        block.call(fake_http)
      end

      yield
    ensure
      Net::HTTP.singleton_class.send(:remove_method, :start)
      Net::HTTP.define_singleton_method(:start, original_start)
    end
  end
end
