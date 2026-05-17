require "open3"
require "tempfile"

module Documents
  class OcrPdfText
    Result = Struct.new(:text, :command_version, :extractor_name, keyword_init: true)

    def self.call(matter_attachment:)
      raise ArgumentError, "Matter attachment source file is not attached" unless matter_attachment.source_file.attached?

      source_tempfile = Tempfile.new([ "source", ".pdf" ])
      sidecar_tempfile = Tempfile.new([ "ocr", ".txt" ])
      output_tempfile = Tempfile.new([ "ocr", ".pdf" ])

      begin
        source_tempfile.binmode
        matter_attachment.source_file.blob.download do |chunk|
          source_tempfile.write(chunk)
        end
        source_tempfile.flush

        command = ENV.fetch("OCR_PDF_COMMAND", "ocrmypdf")
        stdout, stderr, status = Open3.capture3(
          command,
          "--quiet",
          "--sidecar",
          sidecar_tempfile.path,
          source_tempfile.path,
          output_tempfile.path
        )

        unless status.success?
          raise "ocrmypdf failed: #{stderr.presence || stdout.presence || "unknown error"}"
        end

        version_stdout, version_stderr, = Open3.capture3(command, "--version")
        version_output = version_stdout.presence || version_stderr.to_s

        Result.new(
          text: File.read(sidecar_tempfile.path),
          command_version: version_output.lines.first.to_s.strip,
          extractor_name: "ocrmypdf"
        )
      ensure
        source_tempfile.close!
        sidecar_tempfile.close!
        output_tempfile.close!
      end
    rescue Errno::ENOENT => error
      raise "ocrmypdf unavailable: #{error.message}"
    end
  end
end
