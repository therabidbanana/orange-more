require 'orange-core/middleware/base'
require 'omniauth'
require 'openid_dm_store'
require 'uri'

module Orange::Middleware
  # This middleware locks down entire contexts and puts them behind 
  # OmniAuth. By default the OpenID strategy is available, but others can be
  # added.
  class AccessControl < Base
    
    def self.pre_use(builder, *opts)
      orange = builder.orange
      open_id_store = OpenIDDataMapper::DataMapperStore.new
      builder.use OmniAuth::Strategies::OpenID, open_id_store
      builder.use OmniAuth::Strategies::Token, :token
      # Note that the included OAuth keys are valid for localhost tests only
      if orange.options['omniauth_twitter']
        builder.use OmniAuth::Strategies::Twitter, (orange.options['omniauth_twitter']['consumer_key'] || 'mkaMYCidCDSf50qm1I78QQ'), (orange.options['omniauth_twitter']['consumer_secret'] || 'ahNYXlsvpSqoSBAjwcmxdIHiFaQQ7s3gV0DyyzmU7P0')
      end
      if orange.options['omniauth_github']
        builder.use OmniAuth::Strategies::GitHub, (orange.options['omniauth_github']['consumer_key'] || '6c548ddee59949e158dd'), (orange.options['omniauth_github']['consumer_secret'] || 'd0c3adc8a0e079eae711975f43b5bed1dc421f74')
      end
      if orange.options['omniauth_facebook']
        builder.use OmniAuth::Strategies::Facebook, (orange.options['omniauth_facebook']['consumer_key'] || '143536245693466'), (orange.options['omniauth_facebook']['consumer_secret'] || 'f3bce5ebad886ecc16f937b2945b3a3d')
      end
      if orange.options['omniauth_google_apps']
        builder.use OmniAuth::Strategies::GoogleApps, open_id_store, :name => 'google_apps', :domain => orange.options['omniauth_google_apps']['domain']
      end
    end
    
    # Sets up the options for the middleware
    # @param [Hash] opts hash of options
    # @option opts [Boolean] :handle_login Whether the access control system should handle 
    #   presenting the login form, or let other parts of the app do that. 
    
    def init(opts = {})
      defs = {:locked => [:preview, :admin, :orange], :login => '/login', :logout => '/logout',
              :handle_login => true}
      opts = opts.with_defaults!(defs)
      @locked = opts[:locked]
      @login = opts[:login]
      @logout = opts[:logout]
      @handle = opts[:handle_login]
      # orange.load(Orange::UserResource.new, :users)
    end
      
    def packet_call(packet)
      packet['user.uid'] ||= (packet.session['user.uid'] || false)
      packet['user.provider'] ||= (packet.session['user.provider'] || false)
      packet['user.id'] ||= (packet.session['user.id'] || packet['user.uid'] || false)
      packet['omniauth.auth'] = packet.env['omniauth.auth'] || packet.session['omniauth.auth']
      packet['user'] = orange[:users].user_for(packet) unless packet['user.uid'].blank?
      if need_to_handle?(packet)
        ret = handle(packet)
        return ret unless ret.blank? # unless handle_openid returns false, return immediately (no downstream app)
      end
      unless access_allowed?(packet)
        packet.flash['user.after_login'] = packet.request.path
        packet.reroute(@login)
      end
      
      pass packet
    end
    
    def access_allowed?(packet)
      return true unless @locked.include?(packet['route.context'])
      if packet['user.id'] || packet['user.uid']
        # Main_user can always log in (root access)
        if main_user?(packet)
          packet['user.main_user'] = true
          unless packet['user', false]
            # Create a user if one doesn't already exist
            name = packet['user.info', {"name" => nil}]['name'] || "Main User"
            email = packet['user.info', {"email" => nil}]['email'] || "none"
            orange[:users].new(packet, {:orange_identities => 
              [{
                :provider => packet['user.provider'], 
                :uid => packet['user.uid'], 
                :name => name,
                :nickname => packet['user.id'],
                :email => email
              }], 
              :name => name, :orange_site => packet['site'], :no_reroute => true})
            packet['user'] = orange[:users].user_for(packet)
          end
          return true
        else
          return orange[:users].access_allowed?(packet, packet['user.id'])
        end
      else
        return false
      end
    end
    
    def main_user?(packet)
      return false if packet['user.id'].blank?
      # Allow all google apps if set to true
      
      if packet['user.provider'] == 'google_apps' && 
        orange.options['omniauth_google_apps'] && 
        orange.options['omniauth_google_apps']['main_users'] && 
        orange.options['omniauth_google_apps']['domain'] == URI.parse(packet['user.uid']).host
         return true 
      end
      id = packet['user.id'].gsub(/^https?:\/\//, '').gsub(/\/$/, '')
      users = orange.options['main_users'] || []
      # users = users + (orange.options['omniauth_users'] || [])
      users = users.dup.push(orange.options['main_user'])
      users = users.flatten.compact
      matches = users.select{|user| 
        (user == id) || (id == user.gsub(/^https?:\/\//, '').gsub(/\/$/, ''))
      }
      matches.length > 0 ? true : false
    end
    
    def need_to_handle?(packet)
      path = packet['route.path'] || packet.request.path 
      @handle && ([@login, @logout].include?(path.gsub(/\/$/, '')) || path =~ /\/auth\//)
    end
    
    def handle(packet)
      if packet.request.path.gsub(/\/$/, '') == @logout
        packet.session['user.uid'] = nil
        packet.session['user.id'] = nil
        packet.session['user.provider'] = nil
        packet.session['omniauth.auth'] = nil
        packet['user.uid'] = nil
        packet['user.id'] = nil
        packet['user.provider'] = nil
        packet['omniauth.auth'] = nil
        after = packet.flash('user.after_login') || '/'
        packet.reroute(after)
        return false
      end
      path = packet['route.path'] || packet.request.path 
      # If trying to login
      if path.match(/\/auth\/([^\/]+)\/?/)
        packet[:status] = 404
        packet[:content] = "Not found"
        packet.finish
      end
      if auth_match = path.match(/\/auth\/([^\/]+)\/callback/)
        provider = packet['user.provider'] = auth_match[1]
        packet.reroute('/') unless packet['omniauth.auth', false]
        uid = packet['user.uid'] = packet['omniauth.auth']['uid']
        user_info = packet['user.info'] = (packet['omniauth.auth']['user_info'] || {})
        # This statement allows us to use nicknames instead of the uid omniauth gives
        case provider
        when "open_id"
          # Allow email substitution for OpenID from trusted openid providers
          # (we do this because Google and Yahoo OpenIDs aren't known until logging in the first time)
          if uid =~ /^https?:\/\/(www.)?google.com\/accounts/
            packet['user.id'] = user_info["email"]
            packet['user.id'] = packet['user.id'].first if packet['user.id'].kind_of?(Array)
          end
          if uid =~ /^https?:\/\/(www.)?yahoo.com/ || uid =~ /^https?:\/\/(my\.|me\.)?yahoo.com/
            packet['user.id'] = user_info["email"]
            packet['user.id'] = packet['user.id'].first if packet['user.id'].kind_of?(Array)
          end
        when "twitter"
          packet['user.id'] = user_info["nickname"]
        when "github"
          packet['user.id'] = user_info["nickname"]
        when "facebook"
          packet['user.id'] = user_info["nickname"]
        when "token"
          # If logged in with token, redirect to profile right away so they can add a real login.
          packet.flash['message'] = "If you haven't already, please add a login provider."
          packet.flash['user.after_login'] = orange[:users].profile_url(packet)
        end
        after = packet.request.params['redirect_to'] || packet.flash('user.after_login') || '/'
        popup = packet.flash('user.popup')
        
        # Save id into session if we have one.
        packet.session['user.id'] = (packet['user.id'] || packet['user.uid'])
        packet.session['user.uid'] = packet['user.uid']
        packet.session['omniauth.auth'] = packet['omniauth.auth']
        packet.session['user.provider'] = packet['user.provider']
        if(packet.session['user.map_account'] && packet['user'])
          packet['user'].orange_identities.create(:provider => packet['user.provider'], :uid => packet['user.uid'], :name => user_info["name"], :email => user_info["email"] || "none", :nickname => packet['user.id'])
          packet.session['user.map_account'] = false
        end
        
        # If the user was supposed to be going somewhere, redirect there
        if(popup)
          # packet.reroute(after)
          packet['template.disable'] = true
          packet[:content] = '<script>window.opener.handleAuthResponse(\''+after+'\', true);window.close()</script>'
          return packet.finish
        else
          packet.reroute(after)
          false
        end
      elsif path.match(/\/auth\/failure/)
        packet['template.disable'] = true
        packet[:content] = '<script>window.opener.handleAuthResponse(\'\', false);window.close()</script>'
        return packet.finish
      # Show login form, if necessary
      else
        after = packet.request.params['redirect_to'] || packet.flash('user.after_login') || '/'
        packet.reroute(after) if packet['user.uid'] && packet.request.params['map_account'].blank? # Reroute if we're logged in.
        packet.flash['user.after_login'] = after # Reset After Login url.
        if(packet.request.params['map_account'])
          packet.session['user.map_account'] = true
        end
        packet.flash['user.popup'] = true
        packet[:content] = orange[:parser].haml('openid_login.haml', packet)
        return packet.finish
      end
    end # end handle_openid
  end
end
