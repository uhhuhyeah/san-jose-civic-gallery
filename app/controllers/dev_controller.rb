class DevController < ApplicationController
  # Development / test sandbox for the Atlas redesign primitives. The matching
  # routes are wrapped in `if Rails.env.local?` so this controller is unreachable
  # in production. Phase 1 design-system PR — see docs/redesign-plan.md.
  before_action :require_local_env

  def atlas_test
    @sample_now = Time.zone.local(2025, 2, 3, 10, 0)
  end

  private

  def require_local_env
    head :not_found unless Rails.env.local?
  end
end
