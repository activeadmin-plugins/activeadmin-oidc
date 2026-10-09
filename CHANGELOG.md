# Changelog

## 3.0.1

- Fix: the OIDC `filter_parameters` entries now match exact keys instead of substrings. `code_verifier`, `id_token`, `access_token` and `refresh_token` are filtered at any depth; `code`, `state`, `session_state` and `nonce` only at the top level. Host params such as `code_id`, `state_eq` or `order[state]` are no longer hidden in logs (#26).

### Check before upgrading: some params are no longer hidden in logs

Up to 3.0.0, the engine hid every param whose name contained `code`, `state`, `nonce` or one of the token names, at any depth. After upgrading, these values are written to your logs in plain text:

- params whose name only contains one of those words, such as `invite_code`, `reset_code`, `verification_code` or `oauth_state`;
- nested `code`, `state`, `session_state` and `nonce`, such as `user[code]`.

If any of them carry a secret, add them to your own filters, for example in `config/initializers/filter_parameter_logging.rb`:

```ruby
Rails.application.config.filter_parameters += %i[invite_code reset_code verification_code]
```

Your entries are kept alongside the engine's. If your app still has the Rails default list, names containing `token` stay hidden by its `:token` entry.
