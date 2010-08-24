require 'orange-more/disqus/base'

module Orange::Plugins
  class Disqus < Base
    views_dir       File.join(File.dirname(__FILE__), 'views')
    resource    Orange::DisqusResource.new
  end
end

Orange.plugin(Orange::Plugins::Disqus.new)

