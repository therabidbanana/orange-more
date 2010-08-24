require 'orange-more/blog/base'

module Orange::Plugins
  class Blog < Base
    views_dir       File.join(File.dirname(__FILE__), 'views')
    
    resource    Orange::BlogResource.new
    resource    Orange::BlogPostResource.new
  end
end

Orange.plugin(Orange::Plugins::Blog.new)

