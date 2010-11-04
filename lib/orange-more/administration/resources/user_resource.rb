module Orange
  class UserResource < Orange::ModelResource
    use OrangeUser
    call_me :users
    def afterLoad
      orange[:admin].add_link("Settings", :resource => @my_orange_name, :text => 'Users')
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
          openids = u.orange_identities.all(:provider => "openid").map{|oid| oid.uid.gsub(/^https?:\/\//, '').gsub(/\/$/, '') }
          openids.include?(id)
        }
        if(matches.length > 0 && matches.first.allowed?(packet))
          uid = matches.first.orange_identities.all(:provider => "openid").first.uid
          packet.session['user.id'] = uid
          packet['user.id'] = uid
          packet.session['user.uid'] = uid
          packet['user.uid'] = uid
          return true
        else  
          packet['user.id'] = nil
          packet.session['user.id'] = nil
          packet.session['user.uid'] = nil
          packet['user.uid'] = nil
          packet.session['user.provider'] = nil
          packet['user.provider'] = nil
          return false
        end
      end
      u.allowed?(packet)
    end
    
    def user_for(packet)
      id = OrangeIdentity.first(:provider => packet['user.provider'], :uid => packet['user.uid'])
      id ? id.orange_user : nil
    end
    
    def onNew(packet, opts = {})
      params = opts
      sites = params.delete 'sites'
      m = model_class.new(params)
      m.save
      sites.each{|k,v| s = OrangeSite.first(:id => k); m.orange_sites << s if s} if sites
      m
    end
    
    def onSave(packet, obj, params ={})
      sites = params.delete 'sites'
      obj.update(params)
      obj.orange_sites = []
      sites.each{|k,v| s = OrangeSite.first(:id => k); obj.orange_sites << s if s} if sites
      obj.save
    end
    
    def find_extras(packet, mode)
      {:sites => OrangeSite.all}
    end
  end
end