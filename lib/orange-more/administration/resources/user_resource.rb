require 'digest/sha1'

module Orange
  class UserResource < Orange::ModelResource
    use OrangeUser
    call_me :users
    def afterLoad
      orange[:admin].add_link("Settings", :resource => @my_orange_name, :text => 'Users')
    end
    
    def profile_url(packet)
      packet.route_to(:users, :profile, :context => :admin)
    end
    
    def access_allowed?(packet, user)
      id = OrangeIdentity.first(:provider => packet['user.provider'], :uid => packet['user.uid'])
      u = id ? id.orange_user : nil
      unless u
        users = model_class.all
        # Deep open id search (take out trailing slash, etc.)
        return false if user.blank?
        id = user.gsub(/^https?:\/\//, '').gsub(/\/$/, '')
        matches = users.select{|u|
          openids = u.orange_identities.all(:provider => "open_id").map{|oid| oid.uid.gsub(/^https?:\/\//, '').gsub(/\/$/, '') }
          openids.include?(id)
        }
        if(matches.length > 0 && matches.first.allowed?(packet))
          uid = matches.first.orange_identities.all(:provider => "open_id").first.uid
          packet.session['user.id'] = uid
          packet['user.id'] = uid
          packet.session['user.uid'] = uid
          packet['user.uid'] = uid
          return true
        else    
          if(packet['user.provider'] == 'token')
            packet.flash['error'] = 'Invalid or expired token.' 
          else
            packet.flash['error'] = 'Invalid credentials. Make sure you have permission to log in, or try a different acccount'
          end
          packet['user.id'] = nil
          packet['user.uid'] = nil
          packet['user.provider'] = nil
          packet.session['user.id'] = nil
          packet.session['user.uid'] = nil
          packet.session['user.provider'] = nil
          return false
        end
      end
      u.allowed?(packet)
    end
    
    def reset_token(packet, opts = {})
      u = find_one(packet, :show, opts[:resource_id] || packet['route.resource_id'])
      u.reset_token!
      packet.reroute(:users, :orange, u.id, :edit) unless opts[:no_reroute]
    end
    
    def profile(packet, opts = {})
      if(packet['user'])
        edit(packet, {:model => packet['user']})
      else
        list(packet, opts)
      end
    end
    
    def afterNew(packet, obj, opts)
      obj.give_token
      obj.orange_site = packet['site']
      obj
    end
    
    def user_for(packet)
      id = OrangeIdentity.first({:provider => packet['user.provider'], :uid => packet['user.uid']})
      id ? id.orange_user : nil
    end
    
    def find_extras(packet, mode)
      {:sites => OrangeSite.all}
    end
  end
end