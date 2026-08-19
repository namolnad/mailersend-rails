# frozen_string_literal: true

require "json"

module MailersendRails
  module Inbound
    # Everything about an inbound MailerSend post that can be decided without a
    # request object. Pulled out of the controller so the parts most worth getting
    # right -- the header-injection guard and the envelope-recipient stamping --
    # are testable on their own.
    class Payload
      # A plausible single address. Anything else is dropped rather than trusted.
      ADDRESS = /\A[^\s<>@]+@[^\s<>@]+\z/
      MAX_RECIPIENTS = 10

      def self.parse(body)
        new(JSON.parse(body.to_s))
      rescue JSON::ParserError
        new(nil)
      end

      def initialize(data)
        @data = data.is_a?(Hash) ? data : nil
      end

      def parseable? = !@data.nil?

      def to_h = @data || {}

      # MailerSend won't save a route whose endpoint doesn't answer, and it checks
      # by posting {"type": "webhook.test"}.
      def validation_ping? = to_h["type"] == "webhook.test"

      # The complete RFC822 message. MailerSend hands it over intact, which is why
      # there is nothing to rebuild here the way the Mailgun or Postmark ingresses
      # have to.
      def raw_message = to_h.dig("data", "raw")

      def raw_message? = raw_message.to_s.strip != ""

      # Who the message was actually delivered to.
      #
      # Routing keys on the recipient, and the headers frequently don't carry it:
      # a sender who Bcc's you leaves no header at all, because stripping Bcc in
      # transit is the entire point of Bcc. The address survives only in the SMTP
      # envelope.
      def envelope_recipients
        Array(to_h.dig("data", "recipients", "rcptTo"))
          .filter_map { |entry| entry["email"] if entry.is_a?(Hash) }
          .map { |address| address.to_s.strip }
          .grep(ADDRESS)
          .uniq
          .first(MAX_RECIPIENTS)
      end

      # The raw message with X-Original-To prepended for each envelope recipient,
      # the same move Action Mailbox's own Postmark ingress makes.
      #
      # The address filter above is load-bearing: an envelope recipient containing
      # a newline could otherwise add arbitrary headers, or close the header block
      # and forge a body.
      def message_with_envelope_recipients
        headers = envelope_recipients.map { |address| "X-Original-To: #{address}\n" }.join
        return raw_message if headers.empty?

        headers + raw_message.to_s
      end
    end
  end
end
