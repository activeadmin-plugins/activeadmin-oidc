# frozen_string_literal: true

# Local development and `rake spec:all` (run without BUNDLE_GEMFILE)
# default to the ActiveAdmin 3.5 stack. CI selects a specific stack via
# BUNDLE_GEMFILE — see gemfiles/activeadmin_3.5.gemfile (Sprockets/Sassc)
# and gemfiles/activeadmin_4.0.gemfile (Propshaft/importmap/Tailwind).
#
# eval_gemfile keeps a single source of truth: the `gemspec path: ".."`
# inside the eval'd file resolves relative to gemfiles/, i.e. this repo
# root, exactly as it does when CI loads the gemfile directly.
eval_gemfile File.expand_path("gemfiles/activeadmin_3.5.gemfile", __dir__)
