# Changelog

## Unreleased

- Fix: OIDC `filter_parameters` entries are now anchored regexps matching the exact key, so host params such as `code_id`, `postal_code` or `state_eq` are no longer filtered from logs.
