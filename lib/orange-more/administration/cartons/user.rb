require 'orange-core/carton'

class OrangeUser < Orange::Carton
  id
  admin do
    title :name
  end
  has n, :orange_identities
  belongs_to :orange_site
  
  def allowed?(packet)
    if(self.orange_site_id == packet['site'].id)
      true
    else  
      # nil out invalid user
      packet.session['user.id'] = nil
      packet['user.id'] = nil
      false
    end
  end
  
  def give_token
    self.orange_identities.new(:provider => "token", :uid => Digest::SHA1.hexdigest("#{self.name}::#{Time.now.to_s}"))
  end
  
  def reset_token!
    self.orange_identities.all(:provider => "token").destroy
    give_token
    save
  end
end

class OrangeIdentity < Orange::Carton
  id
  admin do
    title :provider, :length => 255
    text :uid, :length => 255
    text :name, :length => 255
    text :email, :length => 255
    belongs :orange_user, 'OrangeUser'
  end
end

class OrangeSite 
  has n, :orange_users
end