# frozen_string_literal: true

# The gem is `rails_mailersend`, so Bundler's auto-require looks for this file. Everything
# lives under `mailersend_rails`, which is the spelling that matches the constant.
#
# The inversion is not a style choice. `mailersend_rails` on RubyGems is an unrelated gem by
# another author, and RubyGems refuses a new name that differs from an existing one only by
# its separators — which rules out `mailersend-rails` as well.
require "mailersend_rails"
