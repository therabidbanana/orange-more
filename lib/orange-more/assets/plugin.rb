require 'orange-more/assets/base'

module Orange::Plugins
  class Assets < Base
    views_dir   File.join(File.dirname(__FILE__), 'views')
    
    resource    Orange::AssetResource.new
  end
end

Orange.plugin(Orange::Plugins::Assets.new)

