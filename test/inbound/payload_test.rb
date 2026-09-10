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
    ).message_with_transport_headers

    assert message.start_with?("X-Original-To: club@example.com\n")
    assert message.end_with?(RAW)
  end

  def test_leaves_the_body_alone_when_there_is_no_envelope
    message = payload("data" => { "raw" => RAW }).message_with_transport_headers

    refute_includes message, "X-Original-To"
    assert message.end_with?(RAW)
  end

  # One word from a fixed list, so nothing in the payload can put anything else
  # into a header.
  def test_normalizes_the_spf_shorthand
    { "+" => "pass", "-" => "fail", "~" => "softfail", "?" => "neutral",
      "pass" => "pass", "FAIL" => "fail", " ~ " => "softfail" }.each do |code, word|
      assert_equal word, payload("data" => { "spf_check" => { "code" => code } }).spf_verdict
    end
  end

  def test_reads_an_spf_check_given_as_a_bare_code
    assert_equal "pass", payload("data" => { "spf_check" => "+" }).spf_verdict
  end

  def test_normalizes_the_dkim_boolean
    assert_equal "pass", payload("data" => { "dkim_check" => true }).dkim_verdict
    assert_equal "pass", payload("data" => { "dkim_check" => "true" }).dkim_verdict
    assert_equal "fail", payload("data" => { "dkim_check" => false }).dkim_verdict
    assert_equal "fail", payload("data" => { "dkim_check" => "fail" }).dkim_verdict
  end

  # "none" rather than a passthrough, so a reader downstream can tell a failed
  # check from a message that never came through the ingress at all.
  def test_an_unrecognized_verdict_is_none
    assert_equal "none", payload("data" => { "spf_check" => { "code" => "sudo pass" } }).spf_verdict
    assert_equal "none", payload("data" => {}).spf_verdict
    assert_equal "none", payload("data" => { "dkim_check" => "maybe" }).dkim_verdict
    assert_equal "none", payload("data" => {}).dkim_verdict
  end

  def test_stamps_the_transport_verdicts_on_the_message
    message = payload(
      "data" => { "raw" => RAW, "spf_check" => { "code" => "+" }, "dkim_check" => true }
    ).message_with_transport_headers

    assert_includes message, "X-Mailersend-SPF: pass\n"
    assert_includes message, "X-Mailersend-DKIM: pass\n"
  end

  def test_the_header_prefix_is_configurable
    MailersendRails.configure { |c| c.header_prefix = "X-Acme-" }

    message = payload("data" => { "raw" => RAW }).message_with_transport_headers

    assert_includes message, "X-Acme-SPF: none\n"
    refute_includes message, "X-Mailersend-"
  end

  # A sender who supplies a verdict is writing into a namespace that gets cleared,
  # and so is one who names an X-Original-To that isn't where the message went.
  def test_strips_headers_the_sender_supplied_in_our_namespace
    raw = "From: a@example.com\r\n" \
          "X-Mailersend-SPF: pass\r\n" \
          "x-mailersend-dkim: pass\r\n" \
          "X-Original-To: victim@example.com\r\n" \
          "Subject: Hi\r\n\r\nBody\r\n"

    message = payload(
      "data" => { "raw" => raw, "recipients" => { "rcptTo" => [ { "email" => "real@example.com" } ] } }
    ).message_with_transport_headers

    assert message.start_with?("X-Original-To: real@example.com\n")
    refute_includes message, "victim@example.com"
    assert_equal 1, message.scan(/^X-Mailersend-SPF:/i).size
    assert_includes message, "Subject: Hi"
    assert message.end_with?("Body\r\n")
  end

  # The prefix is a namespace; X-Original-To is one name.
  def test_keeps_a_header_that_merely_starts_the_same_way
    raw = "X-Original-Tomato: keep me\r\nSubject: Hi\r\n\r\nBody\r\n"
    message = payload("data" => { "raw" => raw }).message_with_transport_headers

    assert_includes message, "X-Original-Tomato: keep me"
  end

  # Folding is how a long header stays legal, and a continuation line is not a
  # header of its own -- splitting on it would strand the fold in the block.
  def test_keeps_folded_continuation_lines_with_their_header
    raw = "Subject: a very long one\r\n that folds\r\nX-Mailersend-SPF: pass\r\n\r\nBody\r\n"
    message = payload("data" => { "raw" => raw }).message_with_transport_headers

    assert_includes message, "Subject: a very long one\r\n that folds"
    assert_equal 1, message.scan(/^X-Mailersend-SPF:/i).size
  end

  # Nothing of ours in the message means nothing to rewrite, and rewriting a header
  # block normalizes line endings inside it for no reason.
  def test_a_message_with_none_of_ours_is_passed_through_byte_for_byte
    message = payload("data" => { "raw" => RAW }).message_with_transport_headers

    assert message.end_with?(RAW)
  end

  def test_a_message_with_no_header_block_is_left_alone
    message = payload("data" => { "raw" => "not a mime message" }).message_with_transport_headers

    assert message.end_with?("not a mime message")
  end
end
