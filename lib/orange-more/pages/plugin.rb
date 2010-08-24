require 'orange-more/pages/base'

module Orange::Plugins
  class Pages < Base
    views_dir       File.join(File.dirname(__FILE__), 'views')
    prerouter   Orange::Middleware::DumbQuotes
    resource    Orange::PageResource.new    
  end
end

Orange.plugin(Orange::Plugins::Pages.new)

