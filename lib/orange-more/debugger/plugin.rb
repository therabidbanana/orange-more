require 'orange-more/debugger/base'
module Orange::Plugins
  class Debugger < Base
    views_dir  File.join(File.dirname(__FILE__), 'views')
    assets_dir  File.join(File.dirname(__FILE__), 'assets')
    prerouter  Orange::Middleware::Debugger
  end
end

Orange.plugin(Orange::Plugins::Debugger.new)

