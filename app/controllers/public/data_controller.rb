module Public
  class DataController < ApplicationController
    def show
      @snapshot = DataHealth::Snapshot.new(jurisdiction: current_jurisdiction)
      fresh_when etag: Public::CacheVersion.data(@snapshot), public: true
    end
  end
end
