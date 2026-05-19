module Public
  class DataController < ApplicationController
    def show
      @snapshot = DataHealth::Snapshot.new
      fresh_when etag: Public::CacheVersion.data, public: true
    end
  end
end
