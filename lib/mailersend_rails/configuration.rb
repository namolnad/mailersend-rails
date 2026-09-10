# frozen_string_literal: true

module MailersendRails
  # Credentials first, ENV as the escape hatch for CI and one-off scripts.
  #
  # Plain Ruby on purpose -- this and the inbound helpers load without Rails, so
  # they can be tested on their own.
  #
  # Every app that copied this code hard-coded the credentials path, which is the
  # main reason the copies drifted: one app keeps the token somewhere else and the
  # file forks. Both sources are checked here so neither app has to patch it.
  class Configuration
    class MissingApiToken < StandardError; end
    class MissingInboundSecret < StandardError; end

    DEFAULT_HEADER_PREFIX = "X-Mailersend-"

    attr_writer :api_token, :inbound_secret
    attr_accessor :log_tag
    attr_reader :header_prefix

    def initialize
      @log_tag = "mailersend"
      @header_prefix = DEFAULT_HEADER_PREFIX
    end

    # The namespace for the headers the ingress stamps onto an arriving message,
    # and the same namespace it clears off one first.
    #
    # Worth setting to the app's own house prefix, and worth setting once: these
    # names are written into messages that are then stored, so changing the prefix
    # later leaves every message already on disk answering to a name nothing reads.
    #
    # Normalized to end in a hyphen, because `X-Acme` and `X-Acme-` differ by one
    # character and the first one produces `X-AcmeSPF`.
    def header_prefix=(value)
      prefix = value.to_s.strip
      raise ArgumentError, "header_prefix cannot be blank" if prefix.empty?

      @header_prefix = prefix.end_with?("-") ? prefix : "#{prefix}-"
    end

    def api_token
      @api_token ||= credential(:api_token) || ENV["MAILERSEND_API_TOKEN"]
    end

    def api_token!
      token = api_token
      return token unless token.nil? || token.empty?

      raise MissingApiToken, "No MailerSend API token. Set credentials mailersend.api_token, " \
                             "or the MAILERSEND_API_TOKEN environment variable. Outbound mail " \
                             "cannot be sent without it."
    end

    # The inbound *route's* secret, shown under the route URL in MailerSend's
    # domain settings. Not the signing secret used for activity webhooks -- they
    # are different values, and swapping them fails every request on signature.
    def inbound_secret
      @inbound_secret ||= credential(:inbound_secret) || ENV["MAILERSEND_INBOUND_SECRET"]
    end

    def inbound_secret?
      secret = inbound_secret
      !(secret.nil? || secret.empty?)
    end

    private
      def credential(key)
        return nil unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

        Rails.application.credentials.dig(:mailersend, key)
      end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_configuration!
      @config = nil
    end
  end
end
