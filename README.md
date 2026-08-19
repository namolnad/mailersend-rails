# mailersend_rails

MailerSend for Rails: an Action Mailer delivery method, and an optional Action
Mailbox ingress for inbound mail.

This existed as a copied `lib/action_mailer/mailersend_delivery.rb` in four apps.
Three of the copies were identical and one had drifted ahead with typed errors and
a nil-text-part fix — which is the usual shape of copied code, and the reason for
the gem.

## Install

```ruby
gem "mailersend_rails"
```

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :mailersend
```

That's the whole outbound setup. Adding the gem registers the delivery method; no
initializer and no `require` of a file under `lib/`.

## Configuration

The token is read from Rails credentials, falling back to the environment:

```yaml
# rails credentials:edit
mailersend:
  api_token: ms_...
  inbound_secret: ...   # only for inbound
```

```bash
MAILERSEND_API_TOKEN=ms_...
MAILERSEND_INBOUND_SECRET=...
```

Or set it explicitly:

```ruby
MailersendRails.configure do |config|
  config.api_token = Vault.read("mailersend/token")
  config.log_tag = "inbound"          # prefixes the ingress log lines
end
```

Delivery failures raise `MailersendRails::DeliveryMethod::DeliveryError` rather
than returning quietly, so the enqueuing job retries and the failure is visible.
For an app where sign-in is by magic link, a swallowed delivery error looks
exactly like a broken app to the person waiting.

## Inbound mail

Optional, and only loads when the app has Action Mailbox. MailerSend posts the
complete RFC822 message, so unlike the Mailgun or Postmark ingresses there is
nothing to rebuild — this hands the message straight to Action Mailbox and lets
`ApplicationMailbox` routing decide what it is.

```ruby
# app/controllers/inbound/mailersend_controller.rb
class Inbound::MailersendController < MailersendRails::Inbound::Controller
end

# config/routes.rb
post "inbound/mailersend" => "inbound/mailersend#create"
```

Point a MailerSend inbound route at that URL and put the route's secret in
`mailersend.inbound_secret`.

Three things it handles that are easy to get wrong:

**The validation ping is answered before the secret is checked.** A route's secret
is generated when the route is saved, so there is no secret to configure until the
route exists — and the route cannot exist while the endpoint refuses the ping for
want of one. Answering first breaks the deadlock. It is safe because it does
nothing: no message read, nothing created, nothing disclosed.

**Envelope recipients are stamped onto the message as `X-Original-To`.** Routing
keys on the recipient, and the headers frequently do not carry it: a sender who
Bccs you leaves no header at all, because stripping Bcc in transit is the entire
point of Bcc. The address survives only in the SMTP envelope. This is the same
move Action Mailbox's own Postmark ingress makes.

**Envelope addresses are filtered before being written into headers.** Header
injection would otherwise be one crafted address away — an address containing a
newline could add arbitrary headers, or close the header block and forge a body.

The signature is verified against the exact bytes MailerSend signed, before
anything parses them; checking against a re-serialised body would verify our own
JSON encoder rather than the sender.

## Tests

```bash
bundle exec rake test
```

The parts most worth getting right — the payload guard rails and signature
verification — are plain Ruby and tested without a Rails app.
