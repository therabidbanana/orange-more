require 'orange-more/cloud/base'

module Orange::Plugins
  class Cloud < Base
    resource    Orange::CloudResource.new
  end
end

Orange.plugin(Orange::Plugins::Cloud.new)

