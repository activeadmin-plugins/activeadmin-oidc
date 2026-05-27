# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = 'please-change-me@example.com'
  require 'devise/orm/active_record'

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = 1
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete

  # router_name pins Devise's URL helpers to AdminPanel::Engine instead
  # of main_app. Without this, *_session_path helpers would be looked
  # up on Rails.application.routes.url_helpers, not the engine's.
  config.router_name = :admin_panel
end
