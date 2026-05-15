require "open3"
require "tempfile"

module Documents
  class ExtractPdfText
    Result = Struct.new(:text, :command_version, keyword_init: true)

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

        stdout, stderr, status = Open3.capture3(
          "pdftotext",
          source_tempfile.path,
          output_tempfile.path
        )

        unless status.success?
          raise "pdftotext failed: #{stderr.presence || stdout.presence || "unknown error"}"
        end

        version_stdout, version_stderr, = Open3.capture3("pdftotext", "-v")
        version_output = version_stdout.presence || version_stderr.to_s

        Result.new(
          text: File.read(output_tempfile.path),
          command_version: version_output.lines.first.to_s.strip
        )
      ensure
        source_tempfile.close!
        output_tempfile.close!
      end
    end
  end
end
