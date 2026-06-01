# frozen_string_literal: true

module AdminPanel
  class Engine < ::Rails::Engine
    # Isolated: URL helpers are namespaced under the engine
    # (`admin_panel.foo_path`), engine routes do NOT merge into
    # main_app helpers, and the engine's mount path PREFIXES every
    # path declared inside.
    #
    # Hosts using this layout must set ActiveAdmin::Oidc.config.login_path
    # relative to the engine mount (e.g. `'/login'` when the engine
    # is mounted at `/admin` — otherwise the default `/admin/login`
    # becomes `/admin/admin/login` after mount prefixing).
    # `config.root` is pinned to this file's directory so Rails picks
    # up the engine's own `config/routes.rb` instead of defaulting to
    # the dummy app's root.
    config.root = __dir__

    isolate_namespace AdminPanel

    engine_name "admin_panel"
  end
end
