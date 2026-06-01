# frozen_string_literal: true

module AdminPanel
  class Engine < ::Rails::Engine
    # Intentionally NOT calling `isolate_namespace AdminPanel`: the
    # admin engine shares route helpers and the main app's url table.
    #
    # `config.root` is pinned to this file's directory so Rails picks
    # up the engine's own `config/routes.rb` (with `devise_for` inside)
    # instead of defaulting to the dummy app's root and re-evaluating
    # the main app's routes file.
    config.root = __dir__

    engine_name "admin_panel"
  end
end
