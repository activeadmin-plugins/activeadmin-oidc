# Changelog

## Unreleased

- Fix: the OIDC `filter_parameters` entries now match exact keys instead of substrings. `code_verifier`, `id_token`, `access_token` and `refresh_token` are filtered at any depth; `code`, `state`, `session_state` and `nonce` only at the top level. Host params such as `code_id`, `state_eq` or `order[state]` are no longer filtered from logs. If you relied on the old substring match to hide params like `invite_code` or `reset_code`, add them to your own `filter_parameters`.
