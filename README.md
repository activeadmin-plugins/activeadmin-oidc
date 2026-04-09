# activeadmin-oidc

> Status: pre-alpha — test plan only. No implementation yet.

OpenID Connect single sign-on for [ActiveAdmin](https://activeadmin.info/), with a first-class [Zitadel](https://zitadel.com/) preset.

This gem plugs generic OIDC SSO into ActiveAdmin's existing Devise stack. It builds on [`omniauth_openid_connect`](https://github.com/omniauth/omniauth_openid_connect) for the OIDC protocol and adds the wiring ActiveAdmin apps actually need: JIT user provisioning, role mapping from provider claims, a Zitadel preset for the nested `urn:zitadel:iam:org:project:roles` claim, a login-view override, and a single install generator.

## Why not just follow the ActiveAdmin wiki?

The [ActiveAdmin OAuth wiki recipe](https://github.com/activeadmin/activeadmin/wiki/Log-in-through-OAuth-providers) is a 200-line copy-paste that only covers Google and doesn't handle role mapping, account linking, or Zitadel's claim shape. This gem packages the wiring once so you can `rails g activeadmin_oidc:install` and be done.

## What this gem does NOT reimplement

The OIDC protocol layer — discovery, JWKS, token verification, PKCE, nonce, state — is delegated to the maintained upstream [`omniauth_openid_connect`](https://github.com/omniauth/omniauth_openid_connect) gem. This gem is a convention-over-configuration wrapper, not a new OIDC client.

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
