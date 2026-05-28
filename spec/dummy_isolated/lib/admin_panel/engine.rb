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
    isolate_namespace AdminPanel

    engine_name "admin_panel"
  end
end
