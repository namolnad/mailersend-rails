# frozen_string_literal: true

require_relative "lib/mailersend_rails/version"

Gem::Specification.new do |spec|
  spec.name          = "mailersend-rails"
  spec.version       = MailersendRails::VERSION
  spec.authors       = [ "Dan Loman" ]
  spec.email         = [ "daniel.h.loman@gmail.com" ]

  spec.summary       = "MailerSend for Rails: an Action Mailer delivery method and an Action Mailbox ingress"
  spec.description   = <<~DESC.strip
    Adds a :mailersend Action Mailer delivery method and, optionally, an inbound
    ingress that hands MailerSend's posted RFC822 message to Action Mailbox --
    including the envelope-recipient stamping that Bcc'd mail depends on.
  DESC
  spec.homepage      = "https://github.com/namolnad/mailersend-rails"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.glob("lib/**/*") + %w[LICENSE README.md]
  spec.require_paths = [ "lib" ]

  # Sending is one POST to a documented JSON endpoint, which net/http out of the
  # standard library does without adding anything to the tree. See DeliveryMethod
  # for why the vendor SDK is not worth its dependencies.
  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "actionmailer", ">= 7.1"
end
