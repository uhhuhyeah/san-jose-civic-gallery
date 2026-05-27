module Public
  class RoundupsController < ApplicationController
    KIND = Generated::SummarizeRoundup::KIND

    def index
      period_ids = Generated::Artifact.succeeded.for_kind(KIND)
        .where(target_type: "Civic::RoundupPeriod").select(:target_id)
      @periods = Civic::RoundupPeriod.for_jurisdiction(current_jurisdiction)
        .where(id: period_ids).recent_first
    end

    def show
      @period = find_period
      raise ActiveRecord::RecordNotFound unless @period

      @artifact = Generated::Artifact.succeeded.for_kind(KIND)
        .where(target: @period).recent_first.first
      raise ActiveRecord::RecordNotFound unless @artifact

      @activity = Public::MonthlyActivity.new(
        jurisdiction: current_jurisdiction,
        period_start: @period.period_start,
        period_end: @period.period_end
      )
    end

    private

    def find_period
      parsed = Date.strptime("#{params[:period]}-01", "%Y-%m-%d")
      Civic::RoundupPeriod.for_jurisdiction(current_jurisdiction).find_by(period_start: parsed)
    rescue ArgumentError
      nil
    end
  end
end
