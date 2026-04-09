# frozen_string_literal: true

require "rails_helper"

RSpec.describe "dummy Rails app boot", type: :request do
  it "mounts ActiveAdmin and redirects unauthenticated requests to login" do
    get "/admin"
    expect(response).to have_http_status(:redirect)
    expect(response.headers["Location"]).to include("login")
  end

  it "wires the gem's omniauth callbacks controller into ActiveAdmin::Devise" do
    expect(ActiveAdmin::Devise.controllers[:omniauth_callbacks])
      .to eq("active_admin/oidc/devise/omniauth_callbacks")
  end
end
