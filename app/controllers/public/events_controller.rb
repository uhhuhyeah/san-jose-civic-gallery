module Public
  class EventsController < ApplicationController
    def index
      @events = Civic::Event.recent_first.limit(25)
    end

    def show
      @event = Civic::Event.find(params[:id])
    end
  end
end
