require 'omniauth/core'

module OmniAuth
  module Strategies
    class Token
      include OmniAuth::Strategy
      
      def request_phase
        return fail!(:missing_information) unless request[:token]
        env['REQUEST_METHOD'] = 'GET'
        env['PATH_INFO'] = request.path + '/callback'
        env['orange.packet']['route.path'] = env['PATH_INFO'] unless (env['orange.packet'].blank?)
        env['orange.packet'].flash['user.after_login'] = request[:redirect_to] unless (request[:redirect_to].blank? || env['orange.packet'].blank?)
        env['omniauth.auth'] = auth_hash(request[:token])
        call_app!
      end
      
      def auth_hash(token)
        OmniAuth::Utils.deep_merge(super(), {
          'uid' => token
        })
      end
      
      def callback_phase
        env['orange.packet'].flash['user.after_login'] = request[:redirect_to] unless (request[:redirect_to].blank? || env['orange.packet'].blank?)
        env['omniauth.auth'] = auth_hash(request[:token])
        call_app!
      end
      
    end
  end
end