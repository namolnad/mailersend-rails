# frozen_string_literal: true

require "test_helper"

class SignatureTest < MailersendRails::TestCase
  Signature = MailersendRails::Inbound::Signature

  BODY = '{"type":"inbound.message"}'
  SECRET = "route-secret"

  def test_accepts_a_matching_signature
    given = Signature.expected(secret: SECRET, body: BODY)
    assert Signature.valid?(secret: SECRET, body: BODY, given: given)
  end

  def test_rejects_the_wrong_secret
    given = Signature.expected(secret: "other", body: BODY)
    refute Signature.valid?(secret: SECRET, body: BODY, given: given)
  end

  # Verifying against a re-serialised body checks our own JSON encoder rather than
  # the sender; key order and whitespace both move.
  def test_rejects_a_body_that_was_re_encoded
    given = Signature.expected(secret: SECRET, body: BODY)
    reencoded = JSON.generate(JSON.parse(BODY).merge("extra" => 1))

    refute Signature.valid?(secret: SECRET, body: reencoded, given: given)
  end

  # Fails closed: an unconfigured secret must not make everything match.
  def test_rejects_when_the_secret_is_blank
    refute Signature.valid?(secret: "", body: BODY, given: Signature.expected(secret: "", body: BODY))
    refute Signature.valid?(secret: nil, body: BODY, given: "anything")
  end

  def test_rejects_a_missing_signature
    refute Signature.valid?(secret: SECRET, body: BODY, given: nil)
    refute Signature.valid?(secret: SECRET, body: BODY, given: "")
  end
end
