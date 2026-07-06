require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "health check endpoint returns success" do
    get "/up"
    assert_response :success
  end

  test "public page sets Content-Security-Policy header" do
    get root_url
    assert_response :success

    csp = response.headers["Content-Security-Policy"]
    assert_not_nil csp, "Expected Content-Security-Policy header to be present"

    assert_includes csp, "default-src 'self'"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "frame-ancestors 'none'"
    assert_includes csp, "base-uri 'self'"
    assert_includes csp, "form-action 'self'"
    assert_includes csp, "img-src 'self' https: data:"
    assert_includes csp, "font-src 'self' data:"
    assert_includes csp, "script-src 'self' https://gc.zgo.at"
    assert_includes csp, "connect-src 'self' https://*.goatcounter.com"
    assert_includes csp, "style-src 'self' 'unsafe-inline'"
  end

  test "health check endpoint does not force SSL redirect in production" do
    skip "force_ssl only active in production environment"
    get "/up", headers: { "X-Forwarded-Proto" => "http" }
    assert_response :success
  end

  test "mission control jobs page renders with CSP header" do
    get "/jobs/"
    assert_response :success

    csp = response.headers["Content-Security-Policy"]
    assert_not_nil csp, "Expected Content-Security-Policy header on Mission Control /jobs"
    assert_includes csp, "default-src 'self'"
  end
end
