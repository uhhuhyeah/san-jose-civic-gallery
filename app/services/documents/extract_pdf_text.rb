require "open3"
require "tempfile"
require "timeout"

module Documents
  class ExtractPdfText
    EXTRACTOR_NAME = "pdftotext".freeze
    DEFAULT_TIMEOUT_SECONDS = 120

    Result = Struct.new(:text, :command_version, :extractor_name, keyword_init: true)

    def self.call(matter_attachment:)
      raise ArgumentError, "Matter attachment source file is not attached" unless matter_attachment.source_file.attached?

      source_tempfile = Tempfile.new([ "source", ".pdf" ])
      output_tempfile = Tempfile.new([ "extracted", ".txt" ])

      begin
        source_tempfile.binmode
        matter_attachment.source_file.blob.download do |chunk|
          source_tempfile.write(chunk)
        end
        source_tempfile.flush

        timeout_seconds = Integer(ENV.fetch("PDFTOTEXT_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS))

        stdout, stderr, status = capture3_with_timeout(
          "pdftotext", source_tempfile.path, output_tempfile.path,
          timeout_seconds:
        )

        unless status.success?
          raise "pdftotext failed: #{stderr.presence || stdout.presence || "unknown error"}"
        end

        version_stdout, version_stderr, = Open3.capture3("pdftotext", "-v")
        version_output = version_stdout.presence || version_stderr.to_s

        Result.new(
          text: File.read(output_tempfile.path),
          command_version: version_output.lines.first.to_s.strip,
          extractor_name: EXTRACTOR_NAME
        )
      ensure
        source_tempfile.close!
        output_tempfile.close!
      end
    end

    def self.capture3_with_timeout(*command_args, timeout_seconds:)
      Timeout.timeout(timeout_seconds) do
        Open3.capture3(*command_args)
      end
    rescue Timeout::Error
      raise "pdftotext timed out after #{timeout_seconds}s"
    end
    private_class_method :capture3_with_timeout
  end
end
