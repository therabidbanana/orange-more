module Orange
  class IdentityResource < Orange::ModelResource
    use OrangeIdentity
    call_me :identities
  end
end