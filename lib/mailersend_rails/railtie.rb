# frozen_string_literal: true

require "rails/railtie"

module MailersendRails
  # The whole point of the gem: adding it registers the delivery method, so an app
  # only has to say `config.action_mailer.delivery_method = :mailersend`.
  class Railtie < ::Rails::Railtie
    initializer "mailersend_rails.delivery_method" do
      ActiveSupport.on_load(:action_mailer) do
        require "mailersend_rails/delivery_method"
        ActionMailer::Base.add_delivery_method :mailersend, MailersendRails::DeliveryMethod
      end
    end

    # Only loaded when the app actually has Action Mailbox, so the gem is usable
    # for outbound alone.
    initializer "mailersend_rails.inbound" do
      ActiveSupport.on_load(:action_controller_base) do
        require "mailersend_rails/inbound/controller" if defined?(ActionMailbox)
      end
    end
  end
end
