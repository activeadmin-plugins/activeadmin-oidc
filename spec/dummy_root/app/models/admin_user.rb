# frozen_string_literal: true

class AdminUser < ApplicationRecord
  devise :omniauthable,
         omniauth_providers: [:oidc]

  validates :email, presence: true

  serialize :oidc_raw_info, coder: JSON

  def active_for_authentication?
    super && enabled?
  end
end
