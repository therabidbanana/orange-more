require 'orange-more/contactforms/base'

module Orange::Plugins
  class ContactForms < Base
    views_dir   File.join(File.dirname(__FILE__), 'views')
    assets_dir  File.join(File.dirname(__FILE__), 'assets')
    resource    Orange::ContactFormsResource.new
  end
end

Orange.plugin(Orange::Plugins::ContactForms.new)

