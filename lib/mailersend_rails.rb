# frozen_string_literal: true

require "mailersend_rails/version"
require "mailersend_rails/configuration"
require "mailersend_rails/inbound/payload"
require "mailersend_rails/inbound/signature"
require "mailersend_rails/railtie" if defined?(::Rails::Railtie)

module MailersendRails
  autoload :DeliveryMethod, "mailersend_rails/delivery_method"

  module Inbound
    autoload :Controller, "mailersend_rails/inbound/controller"
  end
end
