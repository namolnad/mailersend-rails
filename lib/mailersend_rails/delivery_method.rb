# frozen_string_literal: true

require "mailersend-ruby"

module MailersendRails
  # An Action Mailer delivery method for MailerSend.
  #
  # Failures raise rather than returning quietly, so the enqueuing job retries and
  # the error is visible. Swallowing them means a magic link that silently goes
  # nowhere, which looks to the person waiting for it exactly like a broken app.
  class DeliveryMethod
    class DeliveryError < StandardError; end

    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      email = build(mail)
      response = email.send

      return response if success?(response)

      raise DeliveryError, "MailerSend returned #{response.code}: #{response.body}"
    end

    private
      def build(mail)
        email = Mailersend::Email.new(client)

        email.add_subject(mail.subject)
        email.add_html(html_for(mail))
        # Only when there is one: passing nil is rejected by the API rather than
        # treated as absent.
        text = mail.text_part&.body&.decoded
        email.add_text(text) if text.present?

        add_from(email, mail)
        add_recipients(email, mail)
        email
      end

      def html_for(mail)
        mail.html_part&.body&.decoded || mail.body.decoded
      end

      def add_from(email, mail)
        from = Mail::Address.new(mail[:from].to_s)
        email.add_from(email: from.address, name: from.display_name)

        return if mail.reply_to.blank?

        reply_to = Mail::Address.new(mail[:reply_to].to_s)
        email.add_reply_to(email: reply_to.address, name: reply_to.display_name)
      end

      def add_recipients(email, mail)
        each_address(mail[:to]) { |a| email.add_recipients(email: a.address, name: a.display_name) }
        each_address(mail[:cc]) { |a| email.add_cc(email: a.address, name: a.display_name) }
        each_address(mail[:bcc]) { |a| email.add_bcc(email: a.address, name: a.display_name) }
      end

      def each_address(field)
        Array(field).each { |entry| yield Mail::Address.new(entry.to_s) }
      end

      def success?(response)
        response.code.to_s.start_with?("2")
      end

      def client
        @client ||= Mailersend::Client.new(MailersendRails.config.api_token!)
      end
  end
end
