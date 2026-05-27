# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    module Devise
      # Mounted by the engine only when the host's AdminUser model
      # omits :database_authenticatable. Provides the GET /admin/login
      # landing page (the SSO button) and DELETE /admin/logout, which
      # Devise normally mounts as a side effect of the database
      # authentication module.
      #
      # POST /admin/login (password sign-in) is intentionally not
      # provided — without :database_authenticatable there is no
      # password to verify.
      class SessionsController < ::ActiveAdmin::Devise::SessionsController
        # Devise's `new` builds `resource_class.new(sign_in_params)`
        # and calls `clean_up_passwords` — both rely on
        # :database_authenticatable being mixed in. We just need to
        # render the SSO landing view, so skip the parent logic.
        def new
          self.resource = resource_class.new
          render template: 'active_admin/devise/sessions/new'
        end

        # Inherit destroy from Devise::SessionsController — it signs
        # out via warden, which works regardless of authentication
        # modules.
      end
    end
  end
end
