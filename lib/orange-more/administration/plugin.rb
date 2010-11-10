require 'orange-more/administration/base'

module Orange::Plugins
  class Administration < Base
    assets_dir      File.join(File.dirname(__FILE__), 'assets')
    views_dir       File.join(File.dirname(__FILE__), 'views')
    templates_dir   File.join(File.dirname(__FILE__), 'templates')
    
    resource    Orange::AdminResource.new, :admin
    resource    Orange::UserResource.new, :users
    resource    Orange::IdentityResource.new, :identities
    resource    Orange::SiteResource.new
    
    prerouter   Orange::Middleware::SiteLoad
    router   Orange::Middleware::AccessControl
    
  end
end

Orange.plugin(Orange::Plugins::Administration.new)

