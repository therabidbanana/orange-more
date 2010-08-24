require 'orange-more/slices/base'

module Orange::Plugins
  class Slices < Base    
    resource    Orange::Radius.new
    resource    Orange::Slices.new
    
    postrouter  Orange::Middleware::RadiusParser
    
  end
end

Orange.plugin(Orange::Plugins::Slices.new)

