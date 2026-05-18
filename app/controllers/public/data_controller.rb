module Public
  class DataController < ApplicationController
    def show
      @snapshot = DataHealth::Snapshot.new
      fresh_when etag: [ "public-data/v1", @snapshot.cache_key ], public: true
    end
  end
end
