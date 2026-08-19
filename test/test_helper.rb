# frozen_string_literal: true

require "minitest/autorun"
require "mailersend_rails"

module MailersendRails
  class TestCase < Minitest::Test
    def setup
      MailersendRails.reset_configuration!
    end

    def teardown
      MailersendRails.reset_configuration!
      ENV.delete("MAILERSEND_API_TOKEN")
      ENV.delete("MAILERSEND_INBOUND_SECRET")
    end
  end
end
