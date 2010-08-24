require 'orange-core/middleware/base'

module Orange::Middleware
  class DumbQuotes < Base
    
    # Passes packet then parses the return
    def packet_call(packet)
      no_smart_quotes! packet
      pass packet
    end
    
    def no_smart_quotes!(packet)
      deep_clean(packet.request.params) { |s| clean!(s) }
    end
    
    def deep_clean(hash, &block)
      if hash.instance_of? String
        yield(hash)
      elsif hash.kind_of? Hash
        hash.each_key { |h| deep_clean(hash[h]) { |s| block.call(s) } }
      else
        nil
      end
    end
    
    def clean!(string)
      string.gsub! "\342\200\230", "'"
      string.gsub! "\342\200\231", "'"
      string.gsub! "\342\200\234", '"'
      string.gsub! "\342\200\235", '"'
      string.gsub! "\342\200\230", "'"
      string.gsub! "\342\200\231", "'"
      string.gsub! "\xE2\x80\x93", '-'
      string.gsub! "\xE2\x80\x94", '--'
      string.gsub!(/\x82/,',')
      string.gsub!(/\x84/,',,')
      string.gsub!(/\x85/,'...')
      string.gsub!(/\x88/,'^')
      string.gsub!(/\x89/,'o/oo')
      string.gsub!(/\x8b/,'<')
      string.gsub!(/\x8c/,'OE')
      string.gsub!(/\x91|\x92/,"'")
      string.gsub!(/\x93|\x94/,'"')
      string.gsub!(/\x95/,'*')
      string.gsub!(/\x96/,'-')
      string.gsub!(/\x97/,'--')
      string.gsub!(/\x98/,'~')
      string.gsub!(/\x99/,'TM')
      string.gsub!(/\x9b/,'>')
      string.gsub!(/\x9c/,'oe')
    end
  end
end