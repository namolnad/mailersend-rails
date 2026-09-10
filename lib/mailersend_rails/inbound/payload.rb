# frozen_string_literal: true

require "json"

require_relative "../configuration"

module MailersendRails
  module Inbound
    # Everything about an inbound MailerSend post that can be decided without a
    # request object. Pulled out of the controller so the parts most worth getting
    # right -- the header-injection guard, the envelope-recipient stamping and the
    # transport's verdicts -- are testable on their own.
    class Payload
      # A plausible single address. Anything else is dropped rather than trusted.
      ADDRESS = /\A[^\s<>@]+@[^\s<>@]+\z/
      MAX_RECIPIENTS = 10

      # The one header the ingress writes under a name it doesn't own: Action
      # Mailbox's own Postmark ingress writes this, and code downstream looks for
      # it by that name, so it isn't namespaced. It is still ours, though, and a
      # sender's copy of it is cleared with the rest.
      ORIGINAL_TO = "X-Original-To"

      # MailerSend reports SPF in received-SPF shorthand -- `+` pass, `-` fail,
      # `~` softfail, `?` neutral -- and DKIM as a boolean. Each becomes one word
      # from a fixed list, so nothing in the payload can put anything else into a
      # header.
      SPF_CODES = {
        "+" => "pass", "-" => "fail", "~" => "softfail", "?" => "neutral",
        "pass" => "pass", "fail" => "fail", "softfail" => "softfail", "neutral" => "neutral"
      }.freeze

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

      # What MailerSend's own checks made of the sender, in one word each. "none"
      # when it said nothing, so a reader downstream can tell a failed check from
      # a message that never passed through here at all.
      def spf_verdict
        check = to_h.dig("data", "spf_check")
        code = check.is_a?(Hash) ? check["code"] : check

        SPF_CODES.fetch(code.to_s.strip.downcase, "none")
      end

      def dkim_verdict
        case to_h.dig("data", "dkim_check")
        when true, "true", "pass" then "pass"
        when false, "false", "fail" then "fail"
        else "none"
        end
      end

      def spf_header = "#{header_prefix}SPF"

      def dkim_header = "#{header_prefix}DKIM"

      # The raw message with what the transport knew stamped on the front: who it
      # was actually delivered to, and the SPF and DKIM verdicts.
      #
      # The verdicts are the one thing in the payload a forger cannot write, which
      # is what makes them worth carrying -- a From: line is whatever the sender
      # typed, and this is the only evidence about it that arrives from outside the
      # message. Any header of ours the sender supplied is cleared first, so the
      # first one downstream reads is always the ingress's.
      #
      # The address filter above is load-bearing: an envelope recipient containing
      # a newline could otherwise add arbitrary headers, or close the header block
      # and forge a body.
      def message_with_transport_headers
        stamped = envelope_recipients.map { |address| "#{ORIGINAL_TO}: #{address}\n" }
        stamped << "#{spf_header}: #{spf_verdict}\n"
        stamped << "#{dkim_header}: #{dkim_verdict}\n"

        stamped.join + strip_reserved_headers(raw_message.to_s)
      end

      private
        def header_prefix = MailersendRails.config.header_prefix

        # Every header the ingress writes, wherever in the block the sender put it.
        # The prefix is a namespace and everything under it is ours; X-Original-To
        # is one name, so the colon is required and X-Original-Tomato survives.
        def reserved_header
          /\A(?:#{Regexp.escape(ORIGINAL_TO)}\s*:|#{Regexp.escape(header_prefix)})/i
        end

        # Header lines named for us, folded continuations included. Only the header
        # block is touched; the body is the sender's. A message carrying none of
        # ours is returned byte-for-byte, which is the overwhelmingly common case.
        def strip_reserved_headers(raw)
          header_block, separator, body = raw.partition(/\r?\n\r?\n/)
          return raw if separator.empty?

          lines = header_block.split(/\r?\n(?![ \t])/)
          kept = lines.reject { |line| line.match?(reserved_header) }
          return raw if kept.size == lines.size

          kept.join("\n") + separator + body
        end
    end
  end
end
