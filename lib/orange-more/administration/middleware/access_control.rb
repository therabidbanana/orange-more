require 'orange-core/middleware/base'
require 'omniauth'
require 'openid_dm_store'


module Orange::Middleware
  # This middleware locks down entire contexts and puts them behind an openid 
  # login system. Currently only supports a single user id. 
  #
  # 
  class AccessControl < Base
    
    def self.pre_use(builder, *opts)
      builder.use OmniAuth::Strategies::OpenID, OpenIDDataMapper::DataMapperStore.new
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
      orange.load(Orange::UserResource.new, :users)
    end
      
    def packet_call(packet)
      packet['user.uid'] ||= (packet.session['user.uid'] || false)
      packet['user.id'] ||= (packet.session['user.id'] || packet['user.uid'] || false)
      packet['omniauth.auth'] = packet.env['omniauth.auth'] || packet.session['omniauth.auth']
      packet['user'] = orange[:users].user_for(packet) unless packet['user.id'].blank?
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
      if packet['user.id']
        # Main_user can always log in (root access)
        if main_user?(packet)
          unless packet['user', false]
            # Create a user if one doesn't already exist
            name = packet['user.info', {"name" => nil}]['name'] || packet['user.id']
            email = packet['user.info', {"email" => nil}]['email'] || packet['user.id']
            orange[:users].new(packet, :orange_identities => 
              [{
                :provider => :open_id, 
                :uid => packet['user.uid'], 
                :name => name,
                :email => email
              }], 
              :name => name, :no_reroute => true)
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
      @handle && ([@login, @logout].include?(packet.request.path.gsub(/\/$/, '')) || packet.request.path =~ /\/auth\//)
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
      packet.reroute('/') if packet['user.uid'] # Reroute to index if we're logged in.
      
      # If trying to login
      if auth_match = packet.request.path.match(/\/auth\/([^\/]+)\/callback/)
        provider = packet['user.provider'] = auth_match[1]
        
        packet.reroute('/') unless packet['omniauth.auth', false]
        uid = packet['user.uid'] = packet['omniauth.auth']['uid']
        user_info = packet['user.info'] = packet['omniauth.auth']['user_info']
        
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
        end
        after = packet.flash('user.after_login') || '/'
        
        # Save id into session if we have one.
        packet.session['user.id'] = (packet['user.id'] || packet['user.uid'])
        packet.session['user.uid'] = packet['user.uid']
        packet.session['omniauth.auth'] = packet['omniauth.auth']
        packet.session['user.provider'] = packet['user.provider']
        
        # If the user was supposed to be going somewhere, redirect there
        # packet.reroute(after)
        packet[:content] = '<script>window.opener.handleAuthResponse(\''+after+'\', true);window.close()</script>'
        return packet.finish
        # packet['template.disable'] = true
        #         # Check for openid response
        #         if resp = packet.env["rack.openid.response"]
        #           if resp.status == :success
        #             packet['user.uid'] = resp.identity_url
        #             
        #             packet['user.openid.url'] = resp.identity_url
        #             packet['user.openid.response'] = resp
        #             # Load in any registration data gathered
        #             profile_data = {}
        #             # merge the SReg data and the AX data into a single hash of profile data
        #             [ OpenID::SReg::Response, OpenID::AX::FetchResponse ].each do |data_response|
        #               if data_response.from_success_response( resp )
        #                 profile_data.merge! data_response.from_success_response( resp ).data
        #               end
        #             end
        #             packet.session['openid.profile'] = profile_data
        #             packet['openid.profile'] = profile_data
        #             if packet['user.uid'] =~ /^https?:\/\/(www.)?google.com\/accounts/
        #               packet['user.id'] = profile_data["http://axschema.org/contact/email"]
        #               packet['user.id'] = packet['user.id'].first if packet['user.id'].kind_of?(Array)
        #             end
        #             
        #             if packet['user.uid'] =~ /^https?:\/\/(www.)?yahoo.com/ || packet['user.id'] =~ /^https?:\/\/(my\.|me\.)?yahoo.com/
        #               packet['user.id'] = profile_data["http://axschema.org/contact/email"]
        #               packet['user.id'] = packet['user.id'].first if packet['user.id'].kind_of?(Array)
        #             end
        #             
        #             
        #             after = packet.flash('user.after_login') || '/'
        #             
        #             # Save id into session if we have one.
        #             packet.session['user.id'] = (packet['user.id'] || packet['user.uid'])
        #             packet.session['user.uid'] = packet['user.uid']
        #             
        #             # If the user was supposed to be going somewhere, redirect there
        #             packet.reroute(after)
        #             false
        #           else
        #             packet.flash['error'] = resp.status
        #             packet.reroute(@login)
        #             false
        #           end
        #         # Set WWW-Authenticate header if awaiting openid.response
        #         else
        #           packet[:status] = 401
        #           packet[:headers] = {}
        #           id = packet.request.params["openid_identifier"]
        #           id = "http://#{id}" unless id =~ /^https?:\/\//
        #           packet.add_header('WWW-Authenticate', Rack::OpenID.build_header(
        #                 :identifier => id,
        #                 :required => [:email, "http://axschema.org/contact/email"]
        #                 ) 
        #           )
        #           packet[:content] = 'Got openID?'          
        #           return packet.finish
        #         end
      # Show login form, if necessary
      else
        packet[:content] = orange[:parser].haml('openid_login.haml', packet)
        return packet.finish
      end
    end # end handle_openid
  end
end