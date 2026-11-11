# frozen_string_literal: true

module RedmineAws
  module SES
    # The forwarded block in the body of a forward (ForwardedMail), as Gmail
    # and Outlook write it in English and Japanese: Gmail's line
    # "---------- Forwarded message ---------" (「転送されたメッセージ」)
    # before the original's headers, or Outlook's header lines
    # (From:/Sent:/To:/Subject:, 差出人:/送信日時:/宛先:/件名:). The original
    # is built from the block's sender and subject, the text after the block,
    # and the forward's attachments.
    class InlineForward
      GMAIL_MARKER = /\A\s*-{5,}\s*(?:Forwarded message|転送されたメッセージ)\s*-{5,}\s*\z/i
      FIELD = /\A\s*\*?(From|Sent|Date|Subject|To|Cc|差出人|送信者|送信日時|日付|件名|宛先)\*?\s*[:：]\s*(.*)\z/i
      FIELDS = { 'from' => :from, '差出人' => :from, '送信者' => :from, 'sent' => :date, 'date' => :date,
                 '送信日時' => :date, '日付' => :date, 'subject' => :subject, '件名' => :subject }.freeze
      # The header lines of a block, with lines that continue a long To or Cc.
      MAX_HEADER_LINES = 12

      def initialize(mail)
        @mail = mail
      end

      SEPARATOR = /\A\s*[_-]{5,}\s*\z/

      # The text of a message: its text/plain part, or its HTML as Redmine
      # converts it (MailHandler.html_body_to_text).
      def self.text(mail)
        new(mail).send(:text)
      end

      # The original as a Mail::Message and the forwarder's own text before
      # the block; nil without a complete block.
      def parse
        lines = text.to_s.lines(chomp: true)
        start = block_start(lines) or return
        fields, body = block(lines, start)
        sender = address(fields[:from])
        return unless sender && fields[:subject] && fields[:date]

        [build(sender, fields[:subject], body), preamble(lines, start)]
      end

      private

      def text
        plain = part('text/plain')
        return utf8(plain) if plain

        html = part('text/html')
        html && MailHandler.html_body_to_text(utf8(html))
      end

      # The lines before the block, without Gmail's line or Outlook's
      # separator.
      def preamble(lines, start)
        lines.first(start).reject { |line| GMAIL_MARKER.match?(line) || SEPARATOR.match?(line) }.join("\n").strip
      end

      # The first part of the type, or the message itself when it is one
      # part of that type (text/plain when it has no Content-Type).
      def part(type)
        found = @mail.all_parts.find { |p| p.mime_type == type && !p.attachment? }
        found || (@mail if !@mail.multipart? && (@mail.mime_type || 'text/plain') == type)
      end

      def utf8(part)
        Redmine::CodesetUtil.to_utf8(part.body.decoded, Mail::Utilities.pick_encoding(part.charset).to_s)
      end

      # The first header line of the outermost block: after Gmail's line, or
      # Outlook's From line.
      def block_start(lines)
        lines.each_with_index do |line, index|
          return index + 1 if GMAIL_MARKER.match?(line)
          return index if field(line)&.first == :from
        end
        nil
      end

      # The block's fields (the first of each) and the text after it.
      def block(lines, start)
        fields = {}
        index = start
        while index < lines.size && index < start + MAX_HEADER_LINES && lines[index].strip.present?
          name, value = field(lines[index])
          fields[name] ||= value if name
          index += 1
        end
        [fields, lines[index..].to_a.join("\n").strip]
      end

      def field(line)
        match = FIELD.match(line) or return
        name = FIELDS[match[1].downcase]
        name && [name, match[2].strip]
      end

      # "Name <address>", "Name [mailto:address]" (Outlook) or the address.
      def address(value)
        found = value.to_s[/<([^<>\s]+@[^<>\s]+)>/, 1] || value.to_s[/mailto:([^\s\]>]+)/i, 1] ||
                value.to_s[/\A([^\s<>]+@[^\s<>]+)\z/, 1]
        found = found&.downcase
        found if found && URI::MailTo::EMAIL_REGEXP.match?(found)
      end

      def build(sender, subject, body)
        original = Mail.new
        original.from = sender
        original.subject = subject
        original.date = @mail.date || Time.current
        original.charset = 'UTF-8'
        add_body(original, body)
        original
      end

      def add_body(original, body)
        attachments = @mail.attachments
        return text_body(original, body) if attachments.empty?

        original.text_part = text_body(Mail::Part.new, body)
        attachments.each { |a| original.attachments[a.filename.to_s] = { mime_type: a.mime_type, content: a.decoded } }
      end

      def text_body(target, body)
        target.content_type = 'text/plain; charset=UTF-8'
        target.body = body
        target
      end
    end
  end
end
