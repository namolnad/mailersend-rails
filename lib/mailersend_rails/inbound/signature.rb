# frozen_string_literal: true

require "openssl"

module MailersendRails
  module Inbound
    # Verified against the exact bytes MailerSend signed, before anything parses
    # them. A signature checked against a re-serialised body verifies our own JSON
    # encoder rather than the sender -- key order and whitespace both move.
    module Signature
      def self.expected(secret:, body:)
        OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, body.to_s)
      end

      def self.valid?(secret:, body:, given:)
        return false if secret.to_s.empty? || given.to_s.empty?

        secure_compare(expected(secret: secret, body: body), given.to_s)
      end

      def self.secure_compare(a, b)
        if defined?(ActiveSupport::SecurityUtils)
          ActiveSupport::SecurityUtils.secure_compare(a, b)
        else
          a.bytesize == b.bytesize && OpenSSL.secure_compare(a, b)
        end
      end
      private_class_method :secure_compare
    end
  end
end
