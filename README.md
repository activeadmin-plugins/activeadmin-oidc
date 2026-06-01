# activeadmin-oidc

[![CI](https://github.com/activeadmin-plugins/activeadmin-oidc/actions/workflows/ci.yml/badge.svg)](https://github.com/activeadmin-plugins/activeadmin-oidc/actions/workflows/ci.yml)

OpenID Connect single sign-on for [ActiveAdmin](https://activeadmin.info/).

Plugs OIDC into ActiveAdmin's existing Devise stack: JIT user provisioning, an `on_login` hook for host-owned authorization, a login-button view override, and a one-shot install generator. The OIDC protocol layer (discovery, JWKS, token verification, PKCE, nonce, state) is delegated to [`omniauth_openid_connect`](https://github.com/omniauth/omniauth_openid_connect).

Used in production by the authors against [Zitadel](https://zitadel.com/). Other compliant OIDC providers work via the standard omniauth_openid_connect options.

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

## Host-app setup checklist

The generator creates the initializer and migration, but it cannot edit your `active_admin.rb` or `admin_user.rb`. Three things have to be in place:

### 1. `config/initializers/active_admin.rb`

```ruby
config.authentication_method = :authenticate_admin_user!
config.current_user_method   = :current_admin_user
```

Without these, `/admin` is public to anyone and the utility navigation (including the logout button) renders empty.

### 2. `app/models/admin_user.rb`

```ruby
class AdminUser < ApplicationRecord
  devise :omniauthable, omniauth_providers: [:oidc]

  serialize :oidc_raw_info, coder: JSON # Postgres jsonb: drop this line
end
```

OIDC is the only authentication mechanism — `:database_authenticatable`, `encrypted_password`, and password reset / lockable / confirmable flows are not used. The IdP owns identity, recovery, MFA, and lockout. The engine auto-mounts `GET /admin/login` (SSO landing page) and `DELETE /admin/logout` so ActiveAdmin's login link still resolves without Devise's session routes.

### Engine-mounted Devise

If `devise_for :admin_users` lives inside a Rails engine (not the main app routes), set `Devise.router_name = :<engine_name>` in `config/initializers/devise.rb` and pass the same option to `devise_for`. The gem reads `Devise.available_router_name` and mounts its session routes inside that engine's route set, so `<Engine>.routes.url_helpers.new_<scope>_session_path` resolves correctly.

For **isolated** engines (`isolate_namespace ...`) mounted at a prefix (e.g. `mount AdminPanel::Engine => '/admin'`), the engine prepends its mount path to every internal route. The gem's default `login_path = '/admin/login'` would then become `/admin/admin/login`. Configure engine-relative paths in `config/initializers/activeadmin_oidc.rb`:

```ruby
ActiveAdmin::Oidc.configure do |c|
  c.login_path  = '/login'
  c.logout_path = '/logout'
end
```

Non-isolated engines don't need this override.

### 3. `config/initializers/activeadmin_oidc.rb` (generated)

Fill in at minimum `issuer`, `client_id`, and an `on_login` hook. Full reference below.

## What the engine does automatically

The gem's Rails engine handles several things so host apps don't have to:

* **OmniAuth strategy registration** — the engine registers the `:openid_connect` strategy with Devise automatically based on your `ActiveAdmin::Oidc` configuration. You do **not** need to add `config.omniauth` or `config.omniauth_path_prefix` to `devise.rb`.
* **Callback controller** — the engine patches `ActiveAdmin::Devise.controllers` to route OmniAuth callbacks to the gem's controller. No manual `controllers: { omniauth_callbacks: ... }` needed in `routes.rb`.
* **Login view override** — the engine prepends an SSO-only login page (no email/password fields) to the sessions controller's view path. If your host app ships its own `app/views/active_admin/devise/sessions/new.html.erb`, the gem detects it and backs off — your view wins.
* **Session routes** — the engine mounts `GET /admin/login` (renders the SSO landing page) and `DELETE /admin/logout` under `devise_scope`, with the scope name derived from `config.admin_user_class`. Devise normally generates session routes as a side effect of `:database_authenticatable`; without that module the route helpers would not exist and ActiveAdmin's login redirect would 404.
* **Path prefix** — the engine sets `Devise.omniauth_path_prefix` and `OmniAuth.config.path_prefix` to `/admin/auth` so the middleware intercepts requests under ActiveAdmin's mount point. Compatible with Rails 7.2+ and Rails 8's lazy route loading.
* **Parameter filtering** — `code`, `id_token`, `access_token`, `refresh_token`, `state`, and `nonce` are added to `Rails.application.config.filter_parameters`.

## Configuration

```ruby
ActiveAdmin::Oidc.configure do |c|
  # --- Provider endpoints -----------------------------------------------
  c.issuer        = ENV.fetch("OIDC_ISSUER")
  c.client_id     = ENV.fetch("OIDC_CLIENT_ID")
  c.client_secret = ENV.fetch("OIDC_CLIENT_SECRET", nil) # blank ⇒ PKCE public client

  # --- OIDC scopes ------------------------------------------------------
  # c.scope = "openid email profile"

  # --- Redirect URI -----------------------------------------------------
  # Normally auto-derived from the callback route. Set explicitly when
  # behind a reverse proxy, CDN, or when the IdP requires exact matching.
  # c.redirect_uri = "https://admin.example.com/admin/auth/oidc/callback"

  # --- Identity lookup --------------------------------------------------
  # Which AdminUser column to match existing rows against, and which
  # claim on the id_token/userinfo to read for the lookup.
  # c.identity_attribute = :email
  # c.identity_claim     = :email

  # --- AdminUser model resolution ---------------------------------------
  # Accepts a String (lazy constant lookup, recommended) or a Class.
  # Use when your model is not literally ::AdminUser.
  # c.admin_user_class = "Admin::User"

  # --- UI copy ----------------------------------------------------------
  # c.login_button_label    = "Sign in with Corporate SSO"
  # c.access_denied_message = "Your account has no permission to access this admin panel."

  # --- PKCE override ----------------------------------------------------
  # By default PKCE is enabled iff client_secret is blank. Override:
  # c.pkce = true

  # --- Authorization hook (REQUIRED) ------------------------------------
  c.on_login = ->(admin_user, claims) {
    # ... see "The on_login hook" below
    true
  }
end
```

### Option reference

| Option | Default | Purpose |
|---|---|---|
| `issuer` | — (required) | OIDC discovery base URL |
| `client_id` | — (required) | IdP client identifier |
| `client_secret` | `nil` | Blank ⇒ PKCE public client |
| `scope` | `"openid email profile"` | Space-separated OIDC scopes |
| `pkce` | auto | `true` when `client_secret` is blank; overridable |
| `redirect_uri` | `nil` (auto) | Explicit callback URL; needed behind reverse proxies |
| `identity_attribute` | `:email` | AdminUser column used for lookup/adoption |
| `identity_claim` | `:email` | Claim key read from the id_token/userinfo |
| `admin_user_class` | `"AdminUser"` | String or Class for the host's admin user model |
| `login_button_label` | `"Sign in with SSO"` | Label on the login-page button |
| `access_denied_message` | generic | Flash shown on any denial |
| `on_login` | — (required) | Authorization hook; see below |

## The `on_login` hook

`on_login` is the **only** place authorization lives. The gem handles authentication (the user proved who they are via the IdP); deciding whether that user is allowed into the admin panel — and what they can see once they are in — is the host application's problem. The gem does not ship a role model.

### Signature

```ruby
c.on_login = ->(admin_user, claims) {
  # admin_user: an instance of the configured admin_user_class.
  #             Either a pre-existing row (matched by provider/uid or by
  #             identity_attribute) or an unsaved new record.
  # claims:     a Hash of String keys. Contains everything the IdP
  #             returned in the id_token/userinfo, plus the top-level
  #             `sub` (copied from the OmniAuth uid) and `email`
  #             (copied from info.email) for convenience.
  #             access_token / refresh_token / id_token are NEVER
  #             present — they are stripped before this hook runs.
  #
  # Return truthy to allow sign-in.
  # Return falsy (false/nil) to deny: the user sees a generic denial
  # flash and no AdminUser record is persisted or mutated.
  #
  # Any mutations you make to admin_user are persisted automatically
  # after the hook returns truthy.
  #
  # Exceptions raised inside the hook are logged at :error via
  # ActiveAdmin::Oidc.logger and surface to the user as the same
  # generic denial flash — the callback action never 500s.
  true
}
```

### Example A — Zitadel nested project roles claim

Zitadel emits roles under the custom claim `urn:zitadel:iam:org:project:roles`, shaped as `{ "role-name" => { "org-id" => "org-name" } }`. Flatten the keys into a string array on the AdminUser.

```ruby
c.on_login = ->(admin_user, claims) {
  roles = claims["urn:zitadel:iam:org:project:roles"]&.keys || []
  return false if roles.empty?

  admin_user.roles = roles
  admin_user.name  = claims["name"] if claims["name"].present?
  true
}
```

### Example B — department-based gating

```ruby
KNOWN_DEPARTMENTS = %w[ops eng support].freeze

c.on_login = ->(admin_user, claims) {
  dept = claims["department"]
  return false unless KNOWN_DEPARTMENTS.include?(dept)

  admin_user.department = dept
  true
}
```

### Example C — syncing from a standard `groups` claim (Keycloak-style)

```ruby
ADMIN_GROUP = "admins"

c.on_login = ->(admin_user, claims) {
  groups = Array(claims["groups"])
  return false unless groups.include?(ADMIN_GROUP)

  admin_user.super_admin = groups.include?("super-admins")
  true
}
```

## Reading additional claims from the callback

Every key the IdP returns in the id_token or userinfo is passed to `on_login` as part of `claims`. Custom claims work the same as standard ones — just read them by key:

```ruby
c.on_login = ->(admin_user, claims) {
  admin_user.employee_id    = claims["employee_id"]
  admin_user.given_name     = claims["given_name"]
  admin_user.family_name    = claims["family_name"]
  admin_user.locale         = claims["locale"]
  admin_user.email_verified = claims["email_verified"]
  # Nested / structured claims come through as whatever the IdP sent.
  # Zitadel metadata, for instance:
  admin_user.tenant_id      = claims.dig("urn:zitadel:iam:user:metadata", "tenant_id")
  true
}
```

The full claim hash (minus `access_token` / `refresh_token` / `id_token`) is also stored on the admin user as `oidc_raw_info` — a JSON column created by the install generator. Read it later outside the hook for debugging or for showing the user's profile from the IdP:

```ruby
AdminUser.last.oidc_raw_info
# => { "sub" => "...", "email" => "...", "groups" => [...], ... }
```

## Sign-in flow

* A login button is added to the ActiveAdmin sessions page via a prepended view override — no templates to edit.
* Clicking it POSTs to `/admin/auth/oidc` with a Rails CSRF token. The gem loads `omniauth-rails_csrf_protection` so OmniAuth 2.x delegates its authenticity check to Rails' forgery protection and `button_to` just works.
* After a successful callback the user is signed in and redirected to `/admin` (not the host app's `/`, which may not exist).
* **Disabled/locked users are rejected.** Devise's `active_for_authentication?` is checked after provisioning but before sign-in. If your model overrides this method (e.g. to check an `enabled` flag or Devise's `:lockable` module), the guard fires on OIDC sign-in too — the user sees an appropriate flash and is redirected to the login page.
* Logout goes through Devise's stock session destroy. No RP-initiated single-logout ping to the IdP — override the destroy action in your host app if you need that.

## Custom login view

The gem ships a minimal SSO-only login page (a single button, no email/password fields). If you need a different layout — for instance, different branding, an explanatory paragraph, or multiple OmniAuth strategies — drop your own template at:

```
app/views/active_admin/devise/sessions/new.html.erb
```

The engine detects the host-app file and does not prepend its own view, so yours takes precedence with no extra configuration.

## Security notes

### Choice of `identity_attribute`

The `identity_attribute` column is used to adopt existing AdminUser rows on first SSO login — an existing user with that value in that column, and no `provider`/`uid` yet, gets linked to the IdP identity. **Do not** point this at a column the IdP can influence and that is also security-sensitive. Safe choices: `:email`, `:username`, `:employee_id`. Unsafe choices: `:admin`, `:super_admin`, `:password_digest`, `:roles` — anything whose value encodes a permission.

### Unique index on the identity column

To prevent concurrent first-logins from creating two AdminUser rows for the same person, the column used as `identity_attribute` should have a database-level unique index. For the default `:email` case the standard Devise migration already adds this. If you pick a custom attribute, add the index yourself:

```ruby
add_index :admin_users, :employee_id, unique: true
```

The gem also adds a unique `(provider, uid)` partial index in its own install migration.

### What's filtered from logs

The engine merges `code`, `id_token`, `access_token`, `refresh_token`, `state`, and `nonce` into `Rails.application.config.filter_parameters` so a mid-callback crash can't dump them into production logs. Your own `filter_parameters` entries are preserved.

## Logger

The gem logs internal diagnostics (on_login exceptions, omniauth failures) via `ActiveAdmin::Oidc.logger`. It defaults to `Rails.logger` when Rails is booted, falling back to a null logger otherwise. Override by assigning directly:

```ruby
ActiveAdmin::Oidc.logger = MyStructuredLogger.new
```

## Testing

`require "activeadmin/oidc/test_helpers"` exposes `ActiveAdmin::Oidc::TestHelpers` with three methods for stubbing OmniAuth in specs:

```ruby
stub_oidc_sign_in(sub: "alice-sub", claims: { "email" => "alice@example.com", "roles" => ["admin"] })
stub_oidc_failure(:invalid_credentials)
reset_oidc_stubs # call in an after hook
```

Wire them up in `rails_helper.rb`:

```ruby
require "activeadmin/oidc/test_helpers"

RSpec.configure do |config|
  config.include ActiveAdmin::Oidc::TestHelpers
  config.after { reset_oidc_stubs }
end
```

### Optional `oidc_mode:` tag filter

For host apps where OIDC is optional (some envs run without an IdP / `config/oidc.yml`), the gem ships an opt-in RSpec filter that:

* Includes `TestHelpers` only on specs tagged `oidc_mode: true`.
* Skips those specs unless the AdminUser model has `:omniauthable` loaded.
* Runs only OIDC-tagged specs when `CI_RUN_OIDC=true` is set (and excludes them otherwise) — useful for a dedicated CI job.

Install it explicitly:

```ruby
require "activeadmin/oidc/test_helpers"
ActiveAdmin::Oidc::RSpecSupport.install!
```

If OIDC is mandatory for your host app, skip the `install!` call and just include `TestHelpers` directly (above).

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).
