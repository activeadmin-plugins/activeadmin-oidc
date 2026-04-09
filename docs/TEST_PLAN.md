# Test Plan — `activeadmin-oidc`

Locked before implementation. Every class and flow listed here gets a failing
spec first; implementation only exists to make the spec green.

## 1. Strategy

- **TDD** at the unit level: every class gets a failing spec, then the minimum
  implementation to make it pass, then refactor.
- **BDD** at the feature level: user-visible flows are expressed as
  Gherkin-style rspec feature specs against a dummy Rails app.
- **Test pyramid**: many unit specs → fewer request specs → a handful of feature
  specs. No expensive browser automation; OIDC callbacks are pure HTTP and
  `rack_test` is sufficient.
- **No implementation code is written before its spec.** One class, one
  red-green-refactor cycle at a time.
- **Dependency boundary**: the gem *wraps* `omniauth_openid_connect` for the
  OIDC protocol. We do not re-test token signature verification, JWKS handling,
  PKCE, nonce, or state — those belong to the upstream gem. We test our own
  wiring, provisioning, role mapping, generator, and view override.

## 2. Test environment

- `spec/dummy/` — a minimal Rails 7.2 host app with Devise + ActiveAdmin + an
  `AdminUser` model + the gem mounted.
- **webmock** — stubs all HTTP calls to the IdP (discovery, token, userinfo,
  jwks).
- **jwt** gem + a `JwtHelper` — signs fake id_tokens with a test RSA keypair.
- **rspec-rails** with transactional fixtures.
- **rack_test** driver for feature specs.
- SQLite as the dummy app's database (no PG dependency for the gem's own CI).

## 3. Repo-relative file layout

```
spec/
├── spec_helper.rb
├── rails_helper.rb
├── dummy/                          # Rails 7.2 host app
├── support/
│   ├── oidc_stubs.rb               # stub_discovery, stub_token, stub_userinfo, stub_jwks
│   ├── jwt_helper.rb               # build_id_token(claims, kid:)
│   └── feature_helpers.rb
├── unit/
│   ├── configuration_spec.rb
│   ├── discovery_spec.rb
│   ├── role_resolver_spec.rb
│   ├── user_provisioner_spec.rb
│   └── presets/
│       └── zitadel_spec.rb
├── requests/
│   ├── auth_callback_spec.rb
│   └── logout_spec.rb
├── features/
│   ├── sign_in_spec.rb
│   ├── sign_out_spec.rb
│   ├── role_denial_spec.rb
│   └── email_migration_spec.rb
└── generators/
    └── install_generator_spec.rb
```

## 4. Unit test cases (TDD)

### 4.1 `ActiveAdmin::Oidc::Configuration` — `spec/unit/configuration_spec.rb`

1. Has sensible defaults: `callback_path`, `login_button_label`, `scope:
   "openid email profile"`, `clock_skew: 30`, `timeout: 5`.
2. `ActiveAdmin::Oidc.configure { |c| ... }` yields the singleton and memoizes
   it.
3. `#validate!` raises `ConfigurationError` when `issuer` is blank.
4. `#validate!` raises `ConfigurationError` when `client_id` is blank.
5. `#validate!` raises `ConfigurationError` when `client_secret` is blank.
6. `#validate!` raises `ConfigurationError` when **both** `role_map` and
   `role_resolver` are nil.
7. `preset :zitadel` applies Zitadel defaults (claim path, resolver, scope)
   without clobbering user-set values.
8. Accessors exist and round-trip: `role_map=`, `role_resolver=`, `issuer=`,
   `client_id=`, `client_secret=`, `scope=`, `callback_path=`,
   `login_button_label=`, `clock_skew=`, `timeout=`.
9. `#reset!` restores defaults (useful in tests).

### 4.2 `ActiveAdmin::Oidc::Discovery` — `spec/unit/discovery_spec.rb`

This wraps the upstream discovery and normalizes it for our own use.

1. Fetches `<issuer>/.well-known/openid-configuration` via HTTPS.
2. Parses and exposes: `authorization_endpoint`, `token_endpoint`,
   `userinfo_endpoint`, `jwks_uri`, `end_session_endpoint`, `issuer`.
3. Memoizes result on the configuration instance.
4. Overridden endpoints in config **take precedence** over discovered values.
5. Raises `DiscoveryError` on non-2xx HTTP response.
6. Raises `DiscoveryError` on malformed JSON.
7. Respects `config.timeout`; raises `DiscoveryError` on timeout.
8. Verifies the discovered `issuer` matches the configured `issuer`
   (RFC 8414 § 3.3); otherwise raises `DiscoveryError`.

### 4.3 `ActiveAdmin::Oidc::RoleResolver` — `spec/unit/role_resolver_spec.rb`

1. Resolves role from a flat `claim_path => { value => role }` map (e.g.
   `"groups"`).
2. Resolves role from a nested claim path in dot notation (e.g.
   `"realm_access.roles"`).
3. Handles the claim value being a scalar.
4. Handles the claim value being an array — picks the first mapped match in
   array order.
5. Returns `nil` when the map has no match AND no lambda is set.
6. When both map and lambda are set: map wins if it returns a value, else the
   lambda is called.
7. Lambda receives the full claims hash and may return a symbol, string, or
   nil.
8. Rescues exceptions in the lambda, logs them, and returns nil (bad host code
   must not crash the login).
9. Role map keys work as either string or symbol.
10. For Zitadel's nested `urn:zitadel:iam:org:project:roles` hash, correctly
    enumerates role keys (covered fully in the Zitadel preset spec).

### 4.4 `ActiveAdmin::Oidc::UserProvisioner` — `spec/unit/user_provisioner_spec.rb`

1. Creates a new AdminUser when no `(provider, uid)` match and no email match.
2. Matches an existing AdminUser on `(provider, uid)` and updates it.
3. **Email migration**: no `(provider, uid)` match → matches by email → locks
   the row to `(provider, uid)`.
4. Email match is ignored if that row already has a **different**
   `(provider, uid)` (security: prevents account takeover via email spoof).
5. Updates `email` and `oidc_raw_info` on every login.
6. Calls `RoleResolver`; assigns the returned role to the AdminUser.
7. When `RoleResolver` returns nil:
   - Raises `ProvisioningError`.
   - Does **not** create a new AdminUser.
   - Does **not** mutate an existing AdminUser (no role downgrade).
8. No-op if role is unchanged (idempotent `save`).
9. Propagates ActiveRecord validation errors as `ProvisioningError`.
10. Concurrent first-login race: simulate two callbacks for the same
    `(provider, uid)` → exactly one AdminUser exists afterwards (relies on the
    unique index created by the generator migration).
11. Blank `email` claim → raises `ProvisioningError`.
12. `oidc_raw_info` stores only id_token claims; `access_token` and
    `refresh_token` are never persisted.

### 4.5 `ActiveAdmin::Oidc::Presets::Zitadel` — `spec/unit/presets/zitadel_spec.rb`

1. Sets default scope
   `"openid email profile urn:zitadel:iam:org:project:roles"`.
2. Sets role claim path to `"urn:zitadel:iam:org:project:roles"`.
3. Ships a default `role_resolver` that parses Zitadel's nested
   `{role_key => {project_id => role_name}}` hash.
4. Resolver returns the first role key that exists in the configured
   `role_map`.
5. Does not override user-set `issuer`, `client_id`, `client_secret`, or a
   user-set `role_resolver`.

## 5. Request specs

### 5.1 `spec/requests/auth_callback_spec.rb`

1. `GET /admin/auth/oidc` redirects to the IdP's `authorization_endpoint` with
   `response_type=code`, `client_id`, `redirect_uri`, `scope`, `state`,
   `nonce`.
2. `GET /admin/auth/oidc/callback` with valid `code` + matching `state`:
   - Exchanges code for tokens (stubbed).
   - Upstream verifies id_token signature against JWKS (stubbed).
   - Provisions user, signs in, redirects to `/admin`.
   - Sets flash notice.
3. Callback with **mismatched state** → 302 to login with error flash; user
   not signed in. *(Upstream concern; we only verify that we render the
   failure path correctly.)*
4. Callback where provisioner raises `ProvisioningError` ("no role") → redirect
   to `/login` with localized error flash; user not signed in; DB unchanged.
5. Callback with id_token missing `sub` → denied; `ProvisioningError`.
6. Callback with blank email claim → denied; `ProvisioningError`.
7. Successful callback persists the Devise session; a follow-up `/admin`
   request is 200.
8. After successful callback, `AdminUser.oidc_raw_info` contains id_token
   claims but no `access_token`/`refresh_token`.

### 5.2 `spec/requests/logout_spec.rb`

1. `DELETE /admin/logout` with a signed-in user clears the Rails session.
2. Next request to `/admin` is redirected to `/login`.
3. **No HTTP call** is made to the IdP's `end_session_endpoint` (webmock
   asserts).
4. Logging out when already signed out is idempotent (no crash, redirect to
   `/login`).

## 6. Feature specs (BDD, Gherkin-style)

### 6.1 `spec/features/sign_in_spec.rb` — Admin login via OIDC

```gherkin
Feature: Admin login via OIDC

  Scenario: First-time user with valid role signs in
    Given OIDC is configured with the Zitadel preset
    And no AdminUser exists with (provider "oidc", uid "abc123")
    When I visit "/login"
    And I click "Sign in with Zitadel"
    And the IdP returns an id_token with sub "abc123", email "alice@example.com", role "admin"
    Then an AdminUser is created with role "admin"
    And I am on "/admin"
    And I see "Signed in successfully"

  Scenario: Returning user is updated from claims
    Given an AdminUser exists with (provider "oidc", uid "abc123", email "old@example.com", role "manager")
    When I sign in via OIDC with claims { sub: "abc123", email: "new@example.com", role: "admin" }
    Then the AdminUser's email is "new@example.com"
    And the role is "admin"
    And I am on "/admin"

  Scenario: Login page shows only the SSO button
    When I visit "/login"
    Then I see a "Sign in with Zitadel" button
    And I do not see an email field
    And I do not see a password field
```

### 6.2 `spec/features/email_migration_spec.rb`

```gherkin
Feature: Migrating existing password users to SSO

  Scenario: Existing AdminUser without provider/uid is migrated on first SSO login
    Given an AdminUser exists with email "bob@example.com", no provider, no uid
    When I sign in via OIDC with sub "xyz789" and email "bob@example.com"
    Then the AdminUser has provider "oidc" and uid "xyz789"
    And I am signed in as that AdminUser

  Scenario: Email match to a user already locked to a different uid is refused
    Given an AdminUser exists with email "bob@example.com", provider "oidc", uid "other-uid"
    When I sign in via OIDC with sub "xyz789" and email "bob@example.com"
    Then I am redirected to "/login"
    And I see a conflict error
    And no AdminUser is mutated
```

### 6.3 `spec/features/role_denial_spec.rb`

```gherkin
Feature: Users without a mapped role are denied

  Scenario: New user with no mapped role
    Given the role map is { "admin" => :admin }
    When I sign in via OIDC with claims.roles = ["reader"]
    Then no AdminUser is created
    And I am redirected to "/login"
    And I see "Your account has no permission to access this admin panel."

  Scenario: Returning user who lost their role is denied but not downgraded
    Given an AdminUser exists with role "admin", provider "oidc", uid "abc"
    When I sign in via OIDC with sub "abc" and no matching role
    Then I am redirected to "/login" with the permission error
    And the AdminUser's role is still "admin"
```

### 6.4 `spec/features/sign_out_spec.rb`

```gherkin
Feature: Local logout

  Scenario: Signing out clears the local session only
    Given I am signed in as an AdminUser
    When I click "Log out"
    Then I am redirected to "/login"
    And no HTTP request is made to the IdP end_session endpoint
```

## 7. Generator spec — `spec/generators/install_generator_spec.rb`

1. Creates `config/initializers/activeadmin_oidc.rb` containing:
   - An `ActiveAdmin::Oidc.configure do |c|` block.
   - A commented-out `c.preset :zitadel` line.
   - A commented-out sample block with Zitadel issuer / client_id /
     client_secret / role_map.
2. Creates a migration adding `provider:string`, `uid:string`,
   `oidc_raw_info:jsonb` (or `text` on SQLite) to `admin_users`.
3. Adds a unique index on `(provider, uid)` in the migration.
4. Injects `mount ActiveAdmin::Oidc::Engine => "/"` (or similar) into
   `config/routes.rb`, but **only if not already present**.
5. Publishes `app/views/active_admin/devise/sessions/new.html.erb` override.
6. **Idempotent**: running the generator twice does not duplicate the
   migration, initializer, or route mount.
7. Aborts with a clear error if no `AdminUser` model is found.
8. Aborts with a clear error if `devise` or `activeadmin` is not in the host
   app's Gemfile.lock.

## 8. Security test checklist (cross-cutting, verified inline in the specs above)

- [ ] `state` CSRF parameter verified on callback *(delegated to
      omniauth_openid_connect; we spec that the failure path renders
      correctly).*
- [ ] `nonce` stored in session, verified against id_token claim *(same as
      above).*
- [ ] `alg=none` and symmetric-key tokens rejected *(upstream; we spec that
      rejection results in a failed sign-in flow).*
- [ ] `iss` and `aud` verified *(upstream).*
- [ ] id_token `exp` enforced with configurable `clock_skew` *(upstream +
      configuration spec).*
- [ ] No tokens or secrets written to Rails logs — `Rails.application.config
      .filter_parameters` includes `:code`, `:id_token`, `:access_token`,
      `:refresh_token` after `rails g activeadmin_oidc:install`.
- [ ] `oidc_raw_info` stores only id_token claims — never `access_token` or
      `refresh_token` (UserProvisioner spec 4.4.12).
- [ ] Callback `redirect_uri` validated against allow-list; no open redirect.
- [ ] Unique index on `(provider, uid)` enforces identity at the DB level
      (generator spec 7.3, UserProvisioner race spec 4.4.10).
- [ ] Email-based account takeover is blocked: a login whose email matches an
      existing AdminUser row that is already locked to a different
      `(provider, uid)` is refused (UserProvisioner spec 4.4.4, feature spec
      6.2 second scenario).

## 9. TDD implementation order

Each step is a full red → green → refactor cycle before moving to the next.

1. **`Configuration`** — defaults, validation, preset loader.
2. **`JwtHelper` + webmock stubs** in `spec/support/` — test infrastructure;
   no production code.
3. **`Discovery`** — happy path, overrides, error modes.
4. **`RoleResolver`** — map, lambda, nested paths.
5. **`UserProvisioner`** — create, update, email migration, role denial,
   concurrent race.
6. **`Presets::Zitadel`**.
7. **Engine + routes + OmniAuth wiring** (the thin layer over
   `omniauth_openid_connect`).
8. **Auth callback request specs → `SessionsController`**.
9. **Logout request spec** (mostly verifying Devise default behavior + no IdP
   call).
10. **Login view override + feature spec**.
11. **Install generator + generator spec**.
12. **Security hardening pass** using the checklist in §8.

## 10. Assumptions

- `jwt` gem for signing/verifying id_tokens in tests.
- `webmock` for HTTP stubs (no VCR).
- Ruby 3.3+, Rails 7.2+, ActiveAdmin 3+, Devise 4.9+.
- MIT license.
- No CI (GitHub Actions, etc.) in the initial scaffold — can be added later.
- SQLite for `spec/dummy` so the gem's own test suite runs without Postgres.

## 11. Out of scope (explicitly NOT tested here)

- Multi-provider (multi-IdP) registration — design decision locked to single
  provider per app.
- Refresh-token rotation and silent renewal — session TTL follows Devise/Rails
  session lifetime only.
- RP-initiated logout — local logout only; no redirect to
  `end_session_endpoint`.
- Re-implementing OIDC protocol (discovery network layer, JWKS fetching,
  signature verification) — delegated to `omniauth_openid_connect`.
- SAML, OAuth 2.0 without OIDC, OAuth1.
- Non-ActiveAdmin Devise hosts.
