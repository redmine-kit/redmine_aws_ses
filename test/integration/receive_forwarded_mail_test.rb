# frozen_string_literal: true

require_relative '../test_helper'
require_relative 'mail_bucket_helper'

module RedmineAws
  module SES
    # Forwarded email (docs/receiving.md#forwarded-email): by an external mailbox and by members.
    class ReceiveForwardedMailTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include RedmineAws::SES::MailBucketHelper

      FORWARD = File.expand_path('../fixtures/forwarded/gmail_en.eml', __dir__)
      ATTACHED = File.expand_path('../fixtures/forwarded/attached.eml', __dir__)
      SRS = 'support+SRS=44ldt=IX=somenet.foo=rhill@company.example'
      DMARC_FAIL = PASS.merge(dmarc: 'FAIL', dmarc_policy: 'REJECT')

      # Email that an external mailbox forwards to the project's address:
      # imported when SES's SPF check passed for a registered forwarder, by
      # an author the project allows (rhill: registered, not a member).
      def test_email_forwarded_by_an_external_mailbox
        project_setting.update!(forwarders: 'company.example')
        record = nil
        assert_difference('Issue.count', 1) { record = receive(external, verdicts: DMARC_FAIL, envelope_from: SRS) }

        assert_equal 'rhill', Issue.order(:id).last.author.login
        assert_equal SRS.downcase, record.envelope_from
      end

      def test_a_forwarder_whose_spf_check_did_not_pass
        project_setting.update!(forwarders: 'company.example')
        record = receive(external, verdicts: DMARC_FAIL.merge(spf: 'FAIL'), envelope_from: 'support@company.example')

        assert_equal %w[dropped forwarder_spf], [record.status, record.reason]
      end

      # A sender Redmine does not know becomes the anonymous user, even when
      # the project creates users: no user is created from forwarded email.
      def test_automatic_forwarding_never_creates_a_user
        project_setting.update!(forwarders: 'company.example', unknown_user: 'create')
        Role.anonymous.add_permission!(:add_issues)
        record = nil
        assert_no_difference('User.count') do
          record = receive(ses_message(from: 'customer@client.example'), verdicts: DMARC_FAIL, envelope_from: SRS)
        end

        assert_predicate Issue.find(record.issue_id).author, :anonymous?
      end

      # A member's forward: the issue is the original sender's when the
      # project allows it.
      def test_email_forwarded_by_a_member
        issue = member_forward('rhill@somenet.foo')

        assert_equal ['rhill', 'Oven does not heat up'], [issue.author.login, issue.subject]
        assert_equal 'The oven stays cold since yesterday.', issue.description.strip
      end

      # The forwarder watches the issue, and a note by the forwarder says
      # whose email it forwarded.
      def test_the_forwarder_of_a_member_forward
        issue = member_forward('rhill@somenet.foo')

        assert issue.watched_by?(User.find(2))
        notes = "Forwarded the email from rhill@somenet.foo.\n\nA customer's report, please have a look."

        assert_equal([['jsmith', notes]], issue.journals.map { |j| [j.user.login, j.notes] })
      end

      # The note and the watcher follow Redmine's rules for the forwarder:
      # "Add notes", and seeing the issue.
      def test_the_forwarder_s_permissions
        Role.find(1).remove_permission!(:add_issue_notes)
        Role.find(1).update!(issues_visibility: 'own')
        issue = member_forward('rhill@somenet.foo')

        assert_empty issue.journals
        assert_not issue.watched_by?(User.find(2))
      end

      # The forward's own text and attachments stay in the forwarder's note.
      def test_the_forward_s_attachments_stay_in_the_note
        issue = attached_forward(attachment: 'notes.txt')
        journal = issue.journals.last

        assert_includes journal.notes, "A customer's report, attached."
        assert_equal ['notes.txt'], journal.details.select { |d| d.property == 'attachment' }.map(&:value)
        assert_equal %w[notes.txt photo.txt], issue.attachments.map(&:filename).sort
      end

      # A member of the project is not an external sender: the issue is the
      # forwarder's, and the note keeps the original sender.
      def test_a_forward_of_a_member_s_email
        issue = member_forward('dlopper@somenet.foo')

        assert_equal ['jsmith', 'Oven does not heat up'], [issue.author.login, issue.subject]
        assert(issue.journals.any? { |j| j.notes.start_with?('Forwarded the email from dlopper@somenet.foo.') })
      end

      # The original's Cc become watchers with the forwarder's permission,
      # not the author's.
      def test_watchers_from_the_original_need_the_forwarder_s_permission
        [true, false].each do |allowed|
          Role.find(1).public_send(allowed ? :add_permission! : :remove_permission!, :add_issue_watchers)

          assert_equal allowed, attached_forward.watched_by?(User.find(3)), allowed.inspect
        end
      end

      # When Redmine does not take the original (here, the author may not add
      # issues to the private project), the forward is the forwarder's own
      # message: nothing is lost.
      def test_a_forward_that_redmine_does_not_take
        Project.find(1).update!(is_public: false)
        issue = member_forward('rhill@somenet.foo', forwarded_author: 'registered')

        assert_equal ['jsmith', 'Fwd: Oven does not heat up'], [issue.author.login, issue.subject]
        assert_empty issue.journals
      end

      private

      def external
        ses_message(from: 'Robert Hill <rhill@somenet.foo>', to: 'support@company.example')
      end

      def member_forward(sender, **settings)
        project_setting.update!(import_forwarded: true, **settings)
        record = receive(File.binread(FORWARD).sub('customer@client.example', sender))
        Issue.find(record.issue_id)
      end

      # An original from rhill with dlopper in Cc, attached to jsmith's
      # forward (with a file of the forward's own).
      def attached_forward(attachment: nil)
        project_setting.update!(import_forwarded: true)
        raw = File.binread(ATTACHED).sub('From: Customer One <customer@client.example>', 'From: rhill@somenet.foo')
                  .sub("To: support@somenet.foo\n", "To: support@somenet.foo\nCc: dlopper@somenet.foo\n")
        raw = raw.sub("\n--outer--", "\n#{attachment_part(attachment)}--outer--") if attachment
        Issue.find(receive(raw).issue_id)
      end

      def attachment_part(name)
        <<~PART
          --outer
          Content-Type: text/plain; name="#{name}"
          Content-Disposition: attachment; filename="#{name}"

          notes
        PART
      end
    end
  end
end
