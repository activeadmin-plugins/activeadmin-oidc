# Changelog

## Unreleased

- Fix: the OIDC `filter_parameters` entry now matches only the exact top-level keys `code`, `code_verifier`, `state`, `session_state`, `nonce`, `id_token`, `access_token` and `refresh_token`, so host params such as `code_id`, `state_eq` or `order[state]` are no longer filtered from logs. If you relied on the old substring match to hide params like `invite_code` or `reset_code`, add them to your own `filter_parameters`.
