require "open3"
require "tempfile"
require "timeout"

module Documents
  class OcrPdfText
    EXTRACTOR_NAME = "ocrmypdf".freeze
    DEFAULT_LANGUAGES = "eng".freeze
    DEFAULT_TIMEOUT_SECONDS = 600

    Result = Struct.new(:text, :command_version, :extractor_name, keyword_init: true)

    def self.call(matter_attachment:)
      raise ArgumentError, "Matter attachment source file is not attached" unless matter_attachment.source_file.attached?

      source_tempfile = Tempfile.new([ "source", ".pdf" ])
      sidecar_tempfile = Tempfile.new([ "ocr", ".txt" ])

      begin
        source_tempfile.binmode
        matter_attachment.source_file.blob.download do |chunk|
          source_tempfile.write(chunk)
        end
        source_tempfile.flush

        command = ENV.fetch("OCR_PDF_COMMAND", "ocrmypdf")
        languages = ENV.fetch("OCR_PDF_LANGUAGES", DEFAULT_LANGUAGES)
        timeout_seconds = Integer(ENV.fetch("OCR_PDF_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS))

        run_ocr(
          command:,
          languages:,
          skip_text: true,
          source_path: source_tempfile.path,
          sidecar_path: sidecar_tempfile.path,
          timeout_seconds:
        )

        Result.new(
          text: File.read(sidecar_tempfile.path),
          command_version: capture_version(command),
          extractor_name: EXTRACTOR_NAME
        )
      ensure
        source_tempfile.close!
        sidecar_tempfile.close!
      end
    rescue SystemCallError => error
      raise "ocrmypdf unavailable: #{error.message}"
    end

    def self.run_ocr(command:, languages:, skip_text:, source_path:, sidecar_path:, timeout_seconds:)
      stderr_read, stderr_write = IO.pipe
      mode_args = skip_text ? [ "--skip-text" ] : []
      pid = Process.spawn(
        command,
        "--quiet",
        *mode_args,
        "--language", languages,
        "--sidecar", sidecar_path,
        source_path,
        "-",
        out: File::NULL,
        err: stderr_write
      )
      stderr_write.close

      stderr_buffer = "".dup
      reader_thread = Thread.new { stderr_buffer << stderr_read.read.to_s }

      status = wait_with_timeout(pid:, timeout_seconds:)
      reader_thread.join

      unless status.success?
        raise "ocrmypdf failed: #{stderr_buffer.strip.presence || "unknown error"}"
      end
    ensure
      stderr_read.close unless stderr_read.nil? || stderr_read.closed?
      stderr_write.close unless stderr_write.nil? || stderr_write.closed?
    end
    private_class_method :run_ocr

    def self.wait_with_timeout(pid:, timeout_seconds:)
      Timeout.timeout(timeout_seconds) do
        _, status = Process.wait2(pid)
        return status
      end
    rescue Timeout::Error
      terminate_subprocess(pid)
      raise "ocrmypdf timed out after #{timeout_seconds}s"
    end
    private_class_method :wait_with_timeout

    def self.terminate_subprocess(pid)
      Process.kill("TERM", pid)
      Timeout.timeout(5) { Process.wait(pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      # Process already exited / reaped
    rescue Timeout::Error
      Process.kill("KILL", pid) rescue nil
      Process.wait(pid) rescue nil
    end
    private_class_method :terminate_subprocess

    def self.capture_version(command)
      stdout, stderr, status = Open3.capture3(command, "--version")
      return "" unless status.success?

      (stdout.presence || stderr.to_s).lines.first.to_s.strip
    end
    private_class_method :capture_version
  end
end
