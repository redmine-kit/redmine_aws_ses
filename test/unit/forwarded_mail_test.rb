# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # Finding the original in a forward (test/fixtures/forwarded/*.eml).
    class ForwardedMailTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def fixture(name)
        File.binread(File.expand_path("../fixtures/forwarded/#{name}.eml", __dir__))
      end

      def parse(raw, max_bytes: 1_000_000)
        RedmineAws::SES::ForwardedMail.parse(Mail.new(raw), max_bytes: max_bytes)
      end

      def original(name)
        forward = parse(fixture(name))
        assert forward, name
        [forward.sender, Mail.new(forward.raw)]
      end

      def test_inline_forwards_of_gmail_and_outlook
        { 'gmail_en' => ['Oven does not heat up', 'The oven stays cold since yesterday.'],
          'outlook_en' => ['Oven does not heat up', 'The oven stays cold since yesterday.'],
          'gmail_ja' => %w[オーブンが温まらない 昨日からオーブンが温まりません。],
          'outlook_ja' => %w[オーブンが温まらない 昨日からオーブンが温まりません。] }.each do |name, (subject, body)|
          sender, mail = original(name)

          assert_equal 'customer@client.example', sender, name
          assert_equal ['customer@client.example'], mail.from, name
          assert_equal subject, mail.subject, name
          assert_equal body, mail.decoded.force_encoding('UTF-8').strip, name
        end
      end

      # The original as it was, without the headers that would add it to an
      # existing issue.
      def test_a_forward_as_attachment
        sender, mail = original('attached')

        assert_equal 'customer@client.example', sender
        assert_equal 'Oven does not heat up', mail.subject
        assert_nil mail.in_reply_to
        assert_equal ['photo.txt'], mail.attachments.map(&:filename)
      end

      # The outermost block: the original of the forward, which may itself
      # quote a forward.
      def test_nested_forwards
        sender, mail = original('nested')

        assert_equal 'dlopper@somenet.foo', sender
        assert_equal 'Fwd: Oven does not heat up', mail.subject
      end

      def test_the_attachments_of_an_inline_forward
        raw = Mail.new(fixture('gmail_en')).tap { |m| m.add_file(filename: 'photo.txt', content: 'a photo') }.to_s
        mail = Mail.new(parse(raw).raw)

        assert_equal ['photo.txt'], mail.attachments.map(&:filename)
        assert_includes mail.text_part.decoded, 'The oven stays cold since yesterday.'
      end

      # Anything else is not a forward; the message is then imported as the
      # forwarder's own.
      def test_messages_that_are_not_usable_forwards
        not_forwards.each { |name, raw| assert_nil parse(raw), name }
      end

      # The forward's own text and attachments, for the forwarder's note.
      def test_the_forwarder_s_own_text
        assert_equal "A customer's report, please have a look.", parse(fixture('gmail_en')).note_text
        assert_equal '', parse(fixture('outlook_en')).note_text
        assert_equal "A customer's report, attached.", parse(fixture('attached')).note_text
        assert_empty parse(fixture('attached')).note_attachments
      end

      # An attached message is a forward only with Fwd:, FW: or 転送:.
      def test_an_attached_message_without_a_forward_subject
        assert_nil parse(fixture('attached').sub('Subject: FW: ', 'Subject: '))
      end

      def test_the_size_limit_applies_to_the_original
        assert parse(fixture('attached'), max_bytes: 2_000)
        assert_nil parse(fixture('attached'), max_bytes: 200)
        assert_nil parse(fixture('gmail_en'), max_bytes: 100)
      end

      private

      def not_forwards
        gmail = fixture('gmail_en')
        { 'no prefix' => gmail.sub('Subject: Fwd: ', 'Subject: '),
          'another language' => fixture('other_language'),
          'no marker or header lines' => ses_message(subject: 'Fwd: Hello', body: 'Just text.'),
          'no sender in the block' => gmail.sub('From: Customer One <customer@client.example>', 'From: Customer One'),
          'no subject in the block' => gmail.sub("Subject: Oven does not heat up\nTo:", 'To:'),
          'the forwarder itself' => gmail.sub('customer@client.example', 'jsmith@somenet.foo'),
          'a reply to a notification' => gmail.sub("Subject: Oven does not heat up\nTo:",
                                                   "Subject: Re: [eCookbook - Bug #1] Oven\nTo:"),
          'two attached messages' => two_attached }
      end

      def two_attached
        raw = fixture('attached')
        part = raw[%r{--outer\nContent-Type: message/rfc822.*?(?=\n--outer--)}m]
        raw.sub("\n--outer--", "\n#{part}\n--outer--")
      end
    end
  end
end
