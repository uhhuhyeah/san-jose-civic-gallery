require "test_helper"
require "csv"
require "rake"

class AttachmentsNeedsManualUploadTest < ActiveSupport::TestCase
  BEGIN_SENTINEL = "===NEEDS_MANUAL_UPLOAD_CSV_BEGIN===".freeze
  END_SENTINEL = "===NEEDS_MANUAL_UPLOAD_CSV_END===".freeze
  EXPECTED_HEADER = "attachment_id,matter_file,attachment_name,hyperlink,error_status,error_message,pdf_path,reason".freeze

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["attachments:needs_manual_upload"]
    @task.reenable
    @matter = Civic::Matter.create!(
      legistar_matter_id: 99001,
      matter_file: "TEST-99001"
    )
    ENV.delete("STATUS")
  end

  teardown do
    ENV.delete("STATUS")
  end

  test "with no candidates, emits a header-only CSV inside the sentinels" do
    stdout, _stderr = run_task

    body = extract_csv_body(stdout)
    lines = body.lines.map(&:chomp)
    assert_equal [ EXPECTED_HEADER ], lines
  end

  test "emits a 403 row with full URL and parsed error_status" do
    hyperlink = "https://www.sanjoseca.gov/your-government/.../budget.pdf"
    attachment = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 80001,
      name: "Capital Budget",
      hyperlink: hyperlink,
      source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 403 from AkamaiGHost"
    )

    stdout, _stderr = run_task

    rows = parse_csv(stdout)
    assert_equal 1, rows.size

    row = rows.first
    assert_equal attachment.id.to_s, row["attachment_id"]
    assert_equal "TEST-99001", row["matter_file"]
    assert_equal "Capital Budget", row["attachment_name"]
    assert_equal hyperlink, row["hyperlink"]
    assert_equal "403", row["error_status"]
    assert_equal "Documents::SafeHttpClient::HttpError: HTTP 403 from AkamaiGHost", row["error_message"]
    assert_nil row["pdf_path"]
    assert_nil row["reason"]
  end

  test "STATUS env var filters to a single error_status" do
    blocked = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 80002,
      name: "Blocked",
      hyperlink: "https://example.com/blocked.pdf",
      source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 403"
    )
    missing = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 80003,
      name: "Missing",
      hyperlink: "https://example.com/missing.pdf",
      source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 404"
    )

    stdout, _stderr = run_task
    ids = parse_csv(stdout).map { |r| r["attachment_id"] }
    assert_equal [ blocked.id.to_s, missing.id.to_s ].sort, ids.sort

    @task.reenable
    ENV["STATUS"] = "403"
    stdout, _stderr = run_task
    rows = parse_csv(stdout)
    assert_equal 1, rows.size
    assert_equal blocked.id.to_s, rows.first["attachment_id"]
    assert_equal "403", rows.first["error_status"]
  end

  test "CSV escaping survives a hyperlink containing a comma" do
    tricky = "https://example.com/path?a=1,b=2&name=\"weird,thing\""
    attachment = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 80004,
      name: "Comma Hyperlink",
      hyperlink: tricky,
      source_file_import_error: "Net::HTTPError: HTTP 500"
    )

    stdout, _stderr = run_task

    rows = parse_csv(stdout)
    assert_equal 1, rows.size
    assert_equal attachment.id.to_s, rows.first["attachment_id"]
    assert_equal tricky, rows.first["hyperlink"]
  end

  private

  def run_task
    capture_io { @task.execute }
  end

  def extract_csv_body(stdout)
    begin_idx = stdout.index(BEGIN_SENTINEL)
    end_idx = stdout.index(END_SENTINEL)
    refute_nil begin_idx, "expected BEGIN sentinel in stdout:\n#{stdout}"
    refute_nil end_idx, "expected END sentinel in stdout:\n#{stdout}"
    stdout[(begin_idx + BEGIN_SENTINEL.length)...end_idx].sub(/\A\r?\n/, "")
  end

  def parse_csv(stdout)
    CSV.parse(extract_csv_body(stdout), headers: true).map(&:to_h)
  end
end
