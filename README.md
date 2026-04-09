# activeadmin-oidc

OpenID Connect single sign-on for [ActiveAdmin](https://activeadmin.info/), with a first-class [Zitadel](https://zitadel.com/) preset.

This gem plugs generic OIDC SSO into ActiveAdmin's existing Devise stack. It builds on [`omniauth_openid_connect`](https://github.com/omniauth/omniauth_openid_connect) for the OIDC protocol and adds the wiring ActiveAdmin apps actually need: JIT user provisioning, role mapping from provider claims, a Zitadel preset for the nested `urn:zitadel:iam:org:project:roles` claim, a login-view override, and a single install generator.

## Why not just follow the ActiveAdmin wiki?

The [ActiveAdmin OAuth wiki recipe](https://github.com/activeadmin/activeadmin/wiki/Log-in-through-OAuth-providers) is a 200-line copy-paste that only covers Google and doesn't handle role mapping, account linking, or Zitadel's claim shape. This gem packages the wiring once so you can `rails g active_admin:oidc:install` and be done.

## What this gem does NOT reimplement

The OIDC protocol layer — discovery, JWKS, token verification, PKCE, nonce, state — is delegated to the maintained upstream [`omniauth_openid_connect`](https://github.com/omniauth/omniauth_openid_connect) gem. This gem is a convention-over-configuration wrapper, not a new OIDC client.

## Installation

```ruby
# Gemfile
gem "activeadmin-oidc"
```

```sh
bundle install
bin/rails generate active_admin:oidc:install
bin/rails db:migrate
```

Then fill in `config/initializers/activeadmin_oidc.rb` with your issuer and client id.

## Host-app setup checklist

The generator can't modify your `active_admin.rb` or `admin_user.rb` for you. Make sure these are in place — the install generator will print a "next steps" reminder, but you may as well do them up front:

1. **`config/initializers/active_admin.rb`** — uncomment both of these:

   ```ruby
   config.authentication_method = :authenticate_admin_user!
   config.current_user_method   = :current_admin_user
   ```

   Without these, `/admin` is public to anyone and the utility navigation (including the logout button) renders empty.

2. **`app/models/admin_user.rb`** — the Devise call must include `:omniauthable` and declare the `oidc` provider:

   ```ruby
   class AdminUser < ApplicationRecord
     devise :database_authenticatable,
            :rememberable,
            :omniauthable, omniauth_providers: [:oidc]

     serialize :oidc_raw_info, coder: JSON
   end
   ```

3. **`config/initializers/devise.rb`** — ActiveAdmin mounts Devise under `/admin`, so OmniAuth's path prefix has to match:

   ```ruby
   config.omniauth_path_prefix = "/admin/auth"
   ```

4. **`config/initializers/activeadmin_oidc.rb`** (generated) — set at minimum `c.issuer`, `c.client_id`, and an `c.on_login` hook that decides whether a given user is allowed in.

## Sign-in flow

* A login button is added to the ActiveAdmin sessions page via a prepended view override — you don't need to edit any templates.
* Clicking it POSTs to `/admin/auth/oidc` with a Rails CSRF token (the gem forces OmniAuth 2.x's authenticity check to delegate to Rails' forgery protection, so `button_to` just works).
* After a successful callback the user is signed in and redirected directly to `/admin` — the gem doesn't assume the host has a `root` route.
* Logout goes through Devise's stock session destroy; no `end_session_endpoint` ping to the IdP. If you want RP-initiated single-logout, override the destroy action in your host app.

## Status and roadmap

Design and test plan are locked. See [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) for the full TDD/BDD roadmap. Implementation follows red-green-refactor in this order:

1. `Configuration`
2. `Discovery` wrapper over omniauth_openid_connect discovery
3. `RoleResolver`
4. `UserProvisioner`
5. `Presets::Zitadel`
6. Rails engine, routes, `SessionsController`
7. Install generator
8. Security hardening pass

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).
