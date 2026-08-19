# frozen_string_literal: true

require "test_helper"

class PayloadTest < MailersendRails::TestCase
  Payload = MailersendRails::Inbound::Payload

  RAW = "From: a@example.com\r\nSubject: Hi\r\n\r\nBody\r\n"

  def payload(hash) = Payload.parse(JSON.generate(hash))

  # A filter has to ask about `type` before the action can report a bad body, and
  # an exception escaping a filter is a 500 -- which tells MailerSend to retry a
  # body that will never parse.
  def test_parsing_never_raises
    assert_equal false, Payload.parse("not json").parseable?
    assert_equal false, Payload.parse("").parseable?
    assert_equal false, Payload.parse(nil).parseable?
  end

  def test_a_json_array_is_not_a_payload
    refute Payload.parse("[1,2,3]").parseable?
  end

  def test_detects_the_validation_ping
    assert payload("type" => "webhook.test").validation_ping?
    refute payload("type" => "inbound.message").validation_ping?
  end

  def test_reads_the_raw_message
    assert_equal RAW, payload("data" => { "raw" => RAW }).raw_message
    refute payload("data" => {}).raw_message?
    refute payload("data" => { "raw" => "  " }).raw_message?
  end

  def test_extracts_envelope_recipients
    result = payload("data" => {
      "recipients" => { "rcptTo" => [ { "email" => "club@example.com" }, { "email" => "b@example.com" } ] }
    }).envelope_recipients

    assert_equal %w[club@example.com b@example.com], result
  end

  def test_deduplicates_and_caps_recipients
    entries = Array.new(30) { |i| { "email" => "user#{i % 3}@example.com" } }
    result = payload("data" => { "recipients" => { "rcptTo" => entries } }).envelope_recipients

    assert_equal 3, result.size
  end

  # Header injection would otherwise be one crafted address away.
  def test_rejects_addresses_that_could_forge_headers
    entries = [
      { "email" => "ok@example.com" },
      { "email" => "evil@example.com\nBcc: attacker@example.com" },
      { "email" => "no-at-sign" },
      { "email" => "spaces in@example.com" },
      { "email" => "<bracket>@example.com" },
      "not-a-hash"
    ]

    result = payload("data" => { "recipients" => { "rcptTo" => entries } }).envelope_recipients
    assert_equal %w[ok@example.com], result
  end

  # Routing keys on the recipient, and a Bcc'd message carries no header at all --
  # stripping Bcc in transit is the entire point of Bcc.
  def test_stamps_envelope_recipients_onto_the_message
    message = payload(
      "data" => { "raw" => RAW, "recipients" => { "rcptTo" => [ { "email" => "club@example.com" } ] } }
    ).message_with_envelope_recipients

    assert message.start_with?("X-Original-To: club@example.com\n")
    assert message.end_with?(RAW)
  end

  def test_leaves_the_message_alone_when_there_is_no_envelope
    message = payload("data" => { "raw" => RAW }).message_with_envelope_recipients
    assert_equal RAW, message
  end
end
