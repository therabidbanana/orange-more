require 'orange-more/sitemap/base'

module Orange::Plugins
  class Sitemap < Base
    assets_dir      File.join(File.dirname(__FILE__), 'assets')
    views_dir       File.join(File.dirname(__FILE__), 'views')
    
    resource    Orange::SitemapResource.new
    router      Orange::Middleware::FlexRouter
    
  end
end

Orange.plugin(Orange::Plugins::Sitemap.new)

