# frozen_string_literal: true

module AdminPanel
  class Engine < ::Rails::Engine
    # Intentionally NOT calling `isolate_namespace AdminPanel`: this
    # mirrors the pbx-api / yeti-web setup where the admin engine
    # shares route helpers and the main app's url table.
    #
    # Routes are auto-loaded from `<engine_root>/config/routes.rb`,
    # i.e. `spec/dummy_engine/lib/admin_panel/config/routes.rb`.
    engine_name "admin_panel"
  end
end
