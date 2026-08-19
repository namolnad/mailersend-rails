# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < MailersendRails::TestCase
  def test_explicit_configuration_wins
    MailersendRails.configure { |c| c.api_token = "explicit" }
    assert_equal "explicit", MailersendRails.config.api_token
  end

  def test_falls_back_to_the_environment
    ENV["MAILERSEND_API_TOKEN"] = "from-env"
    assert_equal "from-env", MailersendRails.config.api_token
  end

  # Every copy of this code hard-coded the credentials lookup, which is how the
  # copies drifted when one app kept its token somewhere else.
  def test_api_token_bang_explains_itself_when_missing
    error = assert_raises(MailersendRails::Configuration::MissingApiToken) do
      MailersendRails.config.api_token!
    end

    assert_includes error.message, "MAILERSEND_API_TOKEN"
  end

  def test_inbound_secret_is_optional
    refute MailersendRails.config.inbound_secret?

    ENV["MAILERSEND_INBOUND_SECRET"] = "shhh"
    MailersendRails.reset_configuration!
    assert MailersendRails.config.inbound_secret?
  end
end
