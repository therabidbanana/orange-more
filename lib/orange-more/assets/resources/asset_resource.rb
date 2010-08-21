require 'fileutils'
module Orange
  class Orange::Carton
    # Define a helper for input type="text" type database stuff
    # Show in a context if wrapped in one of the helpers
    def self.asset(name, opts = {})
      add_scaffold(name, :asset, Integer, opts)
    end
  end
  
  class AssetResource < Orange::ModelResource
    use OrangeAsset
    call_me :assets
    
    def stack_init
      if orange.options[:s3_bucket]
        require 'aws/s3'
        options[:s3_bucket] = orange.options[:s3_bucket]
        options[:s3_access_key_id] = orange.options[:s3_access_key_id]
        options[:s3_secret_access_key] = orange.options[:s3_secret_access_key]
      end
      orange[:admin, true].add_link("Content", :resource => @my_orange_name, :text => 'Assets')
      orange[:radius, true].define_tag "asset" do |tag|
        if tag.attr['id']
          ret = (m = model_class.first(:id => tag.attr['id'])) ? m.to_asset_tag : 'Invalid Asset'
          if tag.attr['wrap']
            ret = "<div class='#{tag.attr['wrap']}'>#{ret}</div>"
          else
            ret
          end
        else
          ''
        end
      end
      orange[:scaffold].add_scaffold_type(:asset) do |name, val, opts|
        if opts[:show]
          opts[:model].to_asset_tag
        else
          packet = opts[:packet]
          
          asset_html = val ? orange[:assets].asset_html(packet, val) : ""
          ret = "<input type=\"hidden\" value=\"#{val}\" name=\"#{opts[:model_name]}[#{name}]\" />"
          if val.blank?
            ret += "<span class='asset_preview'></span><a class='insert_asset' rel=\"#{opts[:model_name]}[#{name}]\" href='/admin/assets/insert'>Insert Asset</a>"
          else
            ret += "<span class='asset_preview'>#{asset_html}</span><a class='insert_asset' rel=\"#{opts[:model_name]}[#{name}]\" href='/admin/assets/#{val}/change'>Change Asset</a>"
          end
          ret = "<label for=''>#{opts[:display_name]}</label><br />" + ret if opts[:label]
        end
      end
    end
    
    def onNew(packet, params = {})
      m = false
      if(file = params['file'][:tempfile])
        file_path = handle_new_file(params['file'][:filename], file)
        if(params['file2'] && secondary = params['file2'][:tempfile]) 
          secondary_path = handle_new_file(params['file2'][:filename], secondary)
        else
          secondary_path = nil
        end
        
        params['path'] = file_path if file_path
        params['secondary_path'] = secondary_path if secondary_path
        params['mime_type'] = params['file'][:type] if file_path
        params['secondary_mime_type'] = params['file2'][:type] if secondary_path
        params.delete('file')
        params.delete('file2')
        params['s3_bucket'] = options[:s3_bucket] if options[:s3_bucket]
        m = model_class.new(params)
      end
      m
    end
    
    def s3_connect!
      if(options[:s3_bucket])
        id = options[:s3_access_key_id] || ENV['S3_KEY']
        secret = options[:s3_access_key_id] || ENV['S3_SECRET']
        AWS::S3::Base.establish_connection!(
            :access_key_id     => id,
            :secret_access_key => secret
          )
      end
    end
    
    def ensure_dir!
      if(options[:s3_bucket])
        AWS::S3::Bucket.create(options[:s3_bucket]) unless AWS::S3::Bucket.find(options[:s3_bucket])
      else
        FileUtils.mkdir_p(orange.app_dir('assets','uploaded')) unless File.exists?(orange.app_dir('assets','uploaded'))
      end
    end
    
    def handle_new_file(filename, file)
      s3_connect!
      ensure_dir!
      if(options[:s3_bucket])
        filename = unique_s3_name(filename)
        AWS::S3::S3Object.store(filename, file, options[:s3_bucket], :access => :public_read)
      else
        filename = unique_local_name(filename)
        FileUtils.cp(file.path, orange.app_dir('assets','uploaded', filename))
        FileUtils.chmod(0644, orange.app_dir('assets','uploaded', filename))
      end
      return filename
    end
    
    def unique_s3_name(filename)
      return filename unless AWS::S3::S3Object.exists?(filename, options[:s3_bucket])
      i = 1
      extname = File.extname(filename)
      basename = File.basename(filename, extname)
      while AWS::S3::S3Object.exists?("#{basename}_#{i}#{extname}", options[:s3_bucket])
        i += 1
      end
      "#{basename}_#{i}#{extname}"
    end
    
    def unique_local_name(filename)
      return filename unless File.exists?(orange.app_dir('assets','uploaded', filename))
      i = 1
      extname = File.extname(filename)
      basename = File.basename(filename, extname)
      while File.exists?(orange.app_dir('assets', 'uploaded', "#{basename}_#{i}#{extname}"))
        i += 1
      end
      "#{basename}_#{i}#{extname}"
    end
    
    # Creates a new model object and saves it (if a post), then reroutes to the main page
    # @param [Orange::Packet] packet the packet being routed
    def new(packet, opts = {})
      no_reroute = opts.delete(:no_reroute) 
      xhr = packet.request.xhr? || packet.request.params["fake_xhr"]
      if packet.request.post? || !opts.blank?
        params = opts.with_defaults(opts.delete(:params) || packet.request.params[@my_orange_name.to_s] || {})
        before = beforeNew(packet, params)
        obj = onNew(packet, params) if before
        afterNew(packet, obj, params) if before
        obj.save if obj && before
      end
      packet.reroute(@my_orange_name, :orange) unless (xhr || no_reroute)
      packet['template.disable'] = true if xhr
      (xhr ? obj.to_s : obj) || false
    end
    
    def insert(packet, opts = {})
      do_view(packet, :insert, opts)
    end
    
    def change(packet, opts = {})
      do_view(packet, :change, opts)
    end
    
    def find_extras(packet, mode, opts = {})
      {:list => model_class.all}
    end
    
    def onDelete(packet, m, opts = {})
      begin
        if(m.s3_bucket)
          s3_connect!
          AWS::S3::S3Object.delete(m.path, m.s3_bucket) if m.path
          AWS::S3::S3Object.delete(m.secondary_path, m.s3_bucket) if m.secondary_path
        else
          FileUtils.rm(orange.app_dir('assets','uploaded', m.path)) if m.path
          FileUtils.rm(orange.app_dir('assets','uploaded', m.secondary_path)) if m.secondary_path
        end
      rescue
        # Problem deleting file
      end
      m.destroy if m
    end
    
    def asset_html(packet, id = false)
      id ||= packet['route.resource_id']
      m = model_class.get(id)
      m ? m.to_asset_tag : false
    end
  end
end