# frozen_string_literal: true

require "rails_helper"

# Unit coverage for `ActiveAdmin::Oidc::Engine.oidc_enabled?`. The
# predicate gates controller registration, view overrides, and the
# fallback `/admin/login` route mount, so getting it wrong silently
# disables parts of the integration.
RSpec.describe ActiveAdmin::Oidc::Engine do
  before { allow(ActiveAdmin::Oidc.config).to receive(:admin_user_class).and_return(double_klass) }

  let(:double_klass) do
    double("AdminUser", devise_modules: modules).tap do |d|
      allow(d).to receive(:respond_to?).with(:devise_modules).and_return(true)
    end
  end

  describe ".oidc_enabled?" do
    context "model includes :omniauthable" do
      let(:modules) { %i[database_authenticatable omniauthable] }
      it { expect(described_class.oidc_enabled?).to be true }
    end

    context "model has :omniauthable only" do
      let(:modules) { %i[omniauthable] }
      it { expect(described_class.oidc_enabled?).to be true }
    end

    context "model lacks :omniauthable" do
      let(:modules) { %i[database_authenticatable] }
      it { expect(described_class.oidc_enabled?).to be false }
    end
  end
end
