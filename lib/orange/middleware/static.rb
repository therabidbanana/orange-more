require 'orange/middleware/base'
require 'orange/middleware/file'

module Orange::Middleware
  # The Orange::Middleware::Static middleware intercepts requests for static files
  # (javascript files, images, stylesheets, etc) based on the url prefixes
  # passed in the options, and serves them using a Rack::File object. 
  #
  # This differs from Rack::Static in that it can serve from multiple roots
  # to accommodate both Orange static files and site specific ones.
  # urls and root act the same as they do for Rack::Static. Only :libs option acts
  # specially.
  # 
  # Each lib is responsible for responding to static_url and static_dir
  # 
  # Examples:
  #           use Orange::Middleware::Static  :libs => [Orange::Core, AwesomeMod]
  #           use Orange::Middleware::Static  :libs => [Orange::Core, AwesomeMod],
  #                                           :urls => ["/favicon.ico"]
  #
  #         => Example 1 would load a file root for Orange::Core and Awesome Mod
  #             Orange::Core static_url is _orange_, and dir is the
  #             orange lib/assets folder
  #         => Example 2 would also redirect favicon.ico to the assets dir
  #
  # 
  # Note that as a general rule, Orange will assume everything static to be in an
  # /assets/ subfolder, therefore, '/assets' will be prepended to the url given
  # by static_url
  # Also note, that since this is the case - setting up a match for general '/assets'
  # could yield unpredictable results
  #
  # a static_url corresponds to the :module => in the add_css and add_js helpers
  class Static < Base

    def initialize(app, core, options={})
      
      @app = app
      @core = core
      @libs = options[:libs] || [Orange::Core]
      
      @urls = options[:urls] || ["/favicon.ico", "/assets/public"]
      @root = options[:root] || ::File.join(Dir.pwd, 'assets')
      @lib_urls = core.statics

      @file_server = Orange::Middleware::File.new(@root)
    end

    def packet_call(packet)
      path = packet.env["PATH_INFO"]
      can_serve_lib = @lib_urls.select{ |url, server| path.index(url) == 0 }.first
      can_serve = @urls.any?{|url| path.index(url) == 0 }
      
      if can_serve_lib
        lib_url = can_serve_lib.first
        packet['file.root'] = can_serve_lib.last
        packet['route.path'] = path.split(lib_url, 2).last        
        @file_server.call(packet.env)
      elsif can_serve
        packet['route.path'] = path
        @file_server.call(packet.env)
      else
        pass packet
      end
    end

  end
end