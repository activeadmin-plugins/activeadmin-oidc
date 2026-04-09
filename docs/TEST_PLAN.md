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
  wiring, provisioning, the `on_login` hook contract, generator, and view
  override.
- **No gem-owned authorization model.** The gem does not ship a `role` column
  or `RoleResolver`. Authorization lives entirely in the host app's
  `on_login` lambda (§4.3). See §12 "Design rationale" for why.

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
│   ├── user_provisioner_spec.rb
│   └── presets/
│       └── zitadel_spec.rb
├── requests/
│   ├── auth_callback_spec.rb
│   └── logout_spec.rb
├── features/
│   ├── sign_in_spec.rb
│   ├── sign_out_spec.rb
│   ├── access_denied_spec.rb
│   └── identity_migration_spec.rb
└── generators/
    └── install_generator_spec.rb
```

## 4. Unit test cases (TDD)

### 4.1 `ActiveAdmin::Oidc::Configuration` — `spec/unit/configuration_spec.rb`

1. Has sensible defaults: `login_button_label`, `scope:
   "openid email profile"`, `clock_skew: 30`, `timeout: 5`,
   `identity_attribute: :email`, `identity_claim: :email`,
   `access_denied_message` set to a generic English string. The callback
   path is a **hardcoded constant** on the engine (not configurable) —
   `ActiveAdmin::Oidc::Engine::CALLBACK_PATH` — so every host app mounts
   the same path and Zitadel (which supports multiple redirect URIs per
   app) just needs that one path in its allow-list.
2. `ActiveAdmin::Oidc.configure { |c| ... }` yields the singleton and memoizes
   it.
3. `#validate!` raises `ConfigurationError` when `issuer` is blank.
4. `#validate!` raises `ConfigurationError` when `client_id` is blank.
5. `#validate!` does **not** require `client_secret` — blank is allowed
   (public client / PKCE mode).
6. `#validate!` raises `ConfigurationError` when `on_login` is not set or is
   not callable.
7. `#pkce` defaults to `true` when `client_secret` is blank and `false`
   otherwise; explicit `c.pkce = true/false` overrides the default.
8. `preset :zitadel` applies Zitadel defaults (scope, pkce-on-if-no-secret)
   without clobbering user-set values.
9. Accessors exist and round-trip: `issuer=`, `client_id=`, `client_secret=`,
   `scope=`, `login_button_label=`, `clock_skew=`, `timeout=`,
   `identity_attribute=`, `identity_claim=`, `access_denied_message=`,
   `on_login=`, `pkce=`. No `callback_path=` — the path is a hardcoded
   engine constant.
10. `#reset!` restores defaults (useful in tests).

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

### 4.3 `on_login` hook contract — covered in `user_provisioner_spec.rb`

The gem owns **no** authorization logic. The host app's `on_login` lambda is
the single hook that:

- Receives `(admin_user, claims)` where `claims` is the merged
  id_token + userinfo hash.
- Mutates `admin_user` in place (e.g. sets `roles`, `department`,
  `permissions`, whatever columns the host has).
- Returns truthy to allow sign-in; returns falsy to deny.
- May raise an unrelated exception to propagate as a 500 (should be rare —
  normal denials use the falsy-return convention).

The gem tests this contract inside `UserProvisioner` (§4.4), not as a
separate class.

### 4.4 `ActiveAdmin::Oidc::UserProvisioner` — `spec/unit/user_provisioner_spec.rb`

In these specs the dummy app's `AdminUser` has columns `email:string`,
`provider:string`, `uid:string`, `oidc_raw_info:text`, and a test-only
`department:string` column so we can assert the `on_login` hook actually
mutates arbitrary host columns.

1. Creates a new AdminUser when no `(provider, uid)` match and no
   `identity_attribute` match.
2. Matches an existing AdminUser on `(provider, uid)` and updates it.
3. **Identity migration**: no `(provider, uid)` match → matches by
   `config.identity_attribute` (populated from `config.identity_claim`) →
   locks the row to `(provider, uid)`.
4. Identity match is ignored if that row already has a **different**
   `(provider, uid)` (security: prevents account takeover).
5. Updates `oidc_raw_info` on every login.
6. Calls `config.on_login.call(admin_user, claims)`:
   - when it returns truthy → AdminUser is saved and signed in.
   - when it returns falsy → `ProvisioningError` is raised, DB unchanged.
   - host app may mutate ANY column via this hook (test with
     `department = claims["department"]` to prove gem-agnostic behavior).
7. On denial (falsy return):
   - No new AdminUser is created.
   - No existing AdminUser is mutated (no downgrade of privileges).
   - `ProvisioningError#message` is derived from
     `config.access_denied_message`.
8. Idempotent `save`: if `on_login` does not mutate anything, no UPDATE is
   issued.
9. Propagates ActiveRecord validation errors as `ProvisioningError`.
10. Concurrent first-login race: simulate two callbacks for the same
    `(provider, uid)` → exactly one AdminUser exists afterwards (relies on
    the unique index created by the generator migration).
11. Blank identity claim (i.e. `claims[config.identity_claim]` is nil/blank)
    → raises `ProvisioningError`. Covered both for `identity_claim: :email`
    and `identity_claim: :preferred_username` to prove it's claim-agnostic.
12. `oidc_raw_info` stores only id_token claims; `access_token` and
    `refresh_token` are never persisted.
13. If `on_login` itself raises an arbitrary exception, it propagates (the
    gem does not swallow host errors).

### 4.5 `ActiveAdmin::Oidc::Presets::Zitadel` — `spec/unit/presets/zitadel_spec.rb`

The Zitadel preset is intentionally tiny — it only sets transport-layer
defaults. All role/claim parsing lives in the host's `on_login`, not here.

1. Sets default `scope` to `"openid email profile"` when not user-set.
2. Sets `pkce = true` when `client_secret` is blank.
3. Does not touch `pkce` when `client_secret` is set (confidential client).
4. Does not override user-set `issuer`, `client_id`, `client_secret`,
   `scope`, `pkce`, or `on_login`.
5. Is idempotent: calling the preset twice yields the same config.

## 5. Request specs

### 5.1 `spec/requests/auth_callback_spec.rb`

1. `GET /admin/auth/oidc` redirects to the IdP's `authorization_endpoint` with
   `response_type=code`, `client_id`, `redirect_uri`, `scope`, `state`,
   `nonce`, and `code_challenge` when PKCE is on.
2. `GET /admin/auth/oidc/callback` with valid `code` + matching `state`:
   - Exchanges code for tokens (stubbed).
   - Upstream verifies id_token signature against JWKS (stubbed).
   - Provisions user via `UserProvisioner`, signs in, redirects to `/admin`.
   - Sets flash notice.
3. Callback with **mismatched state** → 302 to login with error flash; user
   not signed in. *(Upstream concern; we only verify that we render the
   failure path correctly.)*
4. Callback where `on_login` returns falsy → redirect to `/login` with
   `config.access_denied_message` flash; user not signed in; DB unchanged.
5. Callback with id_token missing `sub` → denied with the same generic
   denial message.
6. Callback with blank `identity_claim` → denied with the same generic
   denial message.
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

  Scenario: First-time user is provisioned via on_login hook
    Given OIDC is configured with a host on_login that assigns department from claims
    And no AdminUser exists with (provider "oidc", uid "abc123")
    When I visit "/login"
    And I click "Sign in with SSO"
    And the IdP returns an id_token with sub "abc123", email "alice@example.com", department "ops"
    Then an AdminUser is created with department "ops"
    And I am on "/admin"
    And I see "Signed in successfully"

  Scenario: Returning user is updated from claims
    Given an AdminUser exists with (provider "oidc", uid "abc123", email "old@example.com", department "eng")
    When I sign in via OIDC with claims { sub: "abc123", email: "new@example.com", department: "ops" }
    Then the AdminUser's email is "new@example.com"
    And the department is "ops"
    And I am on "/admin"

  Scenario: Login page shows only the SSO button
    When I visit "/login"
    Then I see a "Sign in with SSO" button
    And I do not see an email field
    And I do not see a password field
```

### 6.2 `spec/features/identity_migration_spec.rb`

```gherkin
Feature: Migrating existing password users to SSO

  Scenario: Existing AdminUser without provider/uid is migrated on first SSO login
    Given an AdminUser exists with email "bob@example.com", no provider, no uid
    When I sign in via OIDC with sub "xyz789" and email "bob@example.com"
    Then the AdminUser has provider "oidc" and uid "xyz789"
    And I am signed in as that AdminUser

  Scenario: Identity match to a user already locked to a different uid is refused
    Given an AdminUser exists with email "bob@example.com", provider "oidc", uid "other-uid"
    When I sign in via OIDC with sub "xyz789" and email "bob@example.com"
    Then I am redirected to "/login"
    And I see the access-denied message
    And no AdminUser is mutated

  Scenario: Works with a non-email identity attribute
    Given OIDC is configured with identity_attribute :username, identity_claim :preferred_username
    And an AdminUser exists with username "bob", no provider, no uid
    When I sign in via OIDC with sub "xyz789" and preferred_username "bob"
    Then the AdminUser has provider "oidc" and uid "xyz789"
    And I am signed in as that AdminUser
```

### 6.3 `spec/features/access_denied_spec.rb`

```gherkin
Feature: Users whose on_login hook returns falsy are denied

  Scenario: New user rejected by host on_login
    Given on_login returns false when claims.department is blank
    When I sign in via OIDC with no department claim
    Then no AdminUser is created
    And I am redirected to "/login"
    And I see "Your account has no permission to access this admin panel."

  Scenario: Returning user rejected by host on_login is not mutated
    Given an AdminUser exists with department "ops", provider "oidc", uid "abc"
    And on_login returns false when claims.department is blank
    When I sign in via OIDC with sub "abc" and no department claim
    Then I am redirected to "/login" with the access-denied message
    And the AdminUser's department is still "ops"
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
   - Commented-out sample `ENV` reads for issuer / client_id /
     client_secret.
   - A commented-out sample `on_login` lambda showing how to parse
     Zitadel's nested `urn:zitadel:iam:org:project:roles` claim.
   - A commented-out sample `on_login` lambda showing a `department`
     assignment (proves the gem is not role-specific).
2. Creates a migration adding `provider:string`, `uid:string`, and
   `oidc_raw_info:jsonb` (or `text` on SQLite) to `admin_users`. **The
   migration does not add any authorization column** (no `role`, no
   `roles`, no `department`) — those belong to the host app.
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
- [ ] PKCE enabled automatically for public clients (blank `client_secret`)
      *(configuration spec 4.1.7, request spec 5.1.1).*
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
- [ ] Identity-based account takeover is blocked: a login whose identity
      claim matches an existing AdminUser row that is already locked to a
      different `(provider, uid)` is refused (UserProvisioner spec 4.4.4,
      feature spec 6.2 second scenario).
- [ ] **Generic denial message only** — the user-facing flash is always
      `config.access_denied_message` regardless of the internal reason
      (unknown user, `on_login` falsy, malformed id_token). Prevents
      enumeration of valid users vs. valid roles.

## 9. TDD implementation order

Each step is a full red → green → refactor cycle before moving to the next.

1. **`Configuration`** — defaults, validation (no `client_secret`
   requirement), preset loader, `on_login` required.
2. **`JwtHelper` + webmock stubs** in `spec/support/` — test infrastructure;
   no production code.
3. **`Discovery`** — happy path, overrides, error modes.
4. **`UserProvisioner`** — create, update, identity migration, `on_login`
   hook contract, denial path, concurrent race.
5. **`Presets::Zitadel`** — scope + pkce only.
6. **Engine + routes + OmniAuth wiring** (the thin layer over
   `omniauth_openid_connect`, including PKCE branch).
7. **Auth callback request specs → `SessionsController`**.
8. **Logout request spec** (mostly verifying Devise default behavior + no IdP
   call).
9. **Login view override + feature specs**.
10. **Install generator + generator spec** (with sample `on_login`
    snippets for Zitadel and department-style apps).
11. **Security hardening pass** using the checklist in §8.

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
- **Any gem-owned authorization model.** No role column, no role resolver,
  no permission DSL. Host apps own their own authorization columns and
  assign them from claims inside the `on_login` hook.

## 12. Design rationale — why no gem-owned roles

Real host apps carry wildly different authorization shapes:

- **yeti-web** stores a `roles` array of permitted resource names on
  `AdminUser`.
- **Other internal apps** store a single `department` string; authorization
  is done by department membership.
- Vanilla ActiveAdmin ships with **zero** authorization — no `role`,
  `roles`, or anything else.

Any role abstraction the gem tried to own would either (a) be too narrow to
fit all three, or (b) be so generic it would duplicate plain Ruby. So the
gem ships a single hook, `on_login(admin_user, claims)`, and lets each host
app do exactly what it needs:

```ruby
# yeti-web initializer
c.on_login = ->(admin_user, claims) {
  roles = claims["urn:zitadel:iam:org:project:roles"]&.keys || []
  return false if roles.empty?
  admin_user.roles = roles
  true
}

# department-style app initializer
c.on_login = ->(admin_user, claims) {
  dept = claims["department"]
  return false unless KNOWN_DEPARTMENTS.include?(dept)
  admin_user.department = dept
  true
}
```

The hook is called with the merged id_token + userinfo claims after
`(provider, uid)` lookup / identity migration and before `save`. Returning
falsy aborts sign-in with `config.access_denied_message`; returning truthy
saves and signs in.

**One hook vs. two**: one is enough. Everything a host might want to decide
(reject tenant, compare old vs. new privileges, mutate any column) is
available at `on_login` because `admin_user.new_record?` tells you
first-login vs. returning, and the current DB row is unmodified until the
hook returns. Adding a second `before_lookup` hook later is non-breaking
if a real need emerges.
