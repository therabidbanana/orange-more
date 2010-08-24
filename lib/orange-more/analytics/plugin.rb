require 'orange-more/analytics/base'

module Orange::Plugins
  class Analytics < Base
    resource    Orange::AnalyticsResource.new
    prerouter   Orange::Middleware::Analytics
  end
end

Orange.plugin(Orange::Plugins::Analytics.new)