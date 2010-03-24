require 'dm-core'
require 'rack'
require 'rack/builder'

module Orange
  # Declare submodules for later use
  module Pulp; end
  module Mixins; end
  module Plugins; end
  
  attr_accessor :plugins
  
  # Support for plugins
  def self.plugins
    @plugins ||= []
  end
  
  # Allows adding plugins
  def self.plugin(plugin)
    self.plugins << plugin if plugin.kind_of?(Orange::Plugins::Base)
  end
  
  # Allow mixins directly from Orange
  def self.mixin(inc)
    Core.mixin inc
  end
  
  # Allow pulp directly from Orange
  def self.add_pulp(inc)
    Packet.mixin inc
  end
  
  # Core is one of two main sources of interaction for Orange Applications
  # 
  # All portions of Orange based code have access to the Core upon
  # initialization. Orange allows access to individual resources, 
  # and also allows single point for event registration and firing.
  # 
  # Functionality of the core can be extended by loading resources,
  # or by mixins that directly affect the Core. Generally, resources
  # are the less convoluted (easier to debug) way to do it.
  class Core
    # Sets the default options for Orange Applications
    DEFAULT_CORE_OPTIONS = 
      {
        :contexts => [:live, :admin, :orange],
        :default_context => :live,
        :default_resource => :not_found,
        :default_database => 'sqlite3::memory:'
      } unless defined?(DEFAULT_CORE_OPTIONS)
    
    # Args will be set to the @options array. 
    # Block DSL style option setting also available:
    #
    #   orange = Orange::Core.new(:optional_option => 'foo') do
    #     haml true
    #     site_name "Banana"
    #     custom_router MyRouterClass.new
    #   end
    #
    #   orange.options[:site_name] #=> "Banana"
    # 
    # This method calls afterLoad when it is done. Subclasses can override
    # the afterLoad method for initialization needs.
    def initialize(*args, &block)
      @options = Options.new(*args, &block).hash.with_defaults(DEFAULT_CORE_OPTIONS)
      @resources = {}
      @application = false
      @stack = false
      @middleware = []
      @events = {}
      @file = __FILE__
      load(Orange::Parser.new, :parser)
      load(Orange::Mapper.new, :mapper)
      load(Orange::PageParts.new, :page_parts)
      Orange.plugins.each{|p| p.resources.each{|args| load(*args)} if p.has_resources?}
      self.register(:stack_loaded) do |s| 
        @middleware.each{|m| m.stack_init if m.respond_to?(:stack_init)}
        @application.stack_init if @application
      end
      self.register(:stack_reloading){|s| @middleware = []} # Dump middleware on stack reload
      # load(Orange::AdminResource.new, :admin)
      afterLoad
      self
    end
    
    # Returns the orange library directory
    # @return [String] the directory name indicating where the core file is
    #   located
    def core_dir(*args)
      if args
        File.join((options[:core_dir] ||= File.dirname(__FILE__)), *args)
      else
        options[:core_dir] ||= File.dirname(__FILE__)
      end
    end
    
    # Returns the directory of the currently executing file (using Dir.pwd),
    # can be overriden using the option :app_dir in initialization
    # 
    # @return [String] the directory name of the currently running application
    def app_dir(*args)
      if args
        File.join((options[:app_dir] ||= Dir.pwd), *args)
      else
        options[:app_dir] ||= Dir.pwd
      end
    end
    
    # Called by initialize after finished loading
    def afterLoad
      true
    end
    
    # Returns status of a given resource by short name
    # @param [Symbol] resource_name The short name of the resource
    # @return [Boolean] result of has_key? in the resources list
    def loaded?(resource_name)
      @resources.has_key?(resource_name)
    end
    
    # Takes an instance of a Orange::Resource subclass, sets orange
    # then adds it to the orange resources
    # 
    # It can be assigned a short name to be used for accessing later
    # on. If no short name is assigned, one will be generated by downcasing
    # the class name and changing it to a symbol
    #
    # Resources must respond to set_orange, which is automatically used to 
    # create a link back to the Core, and to notify the resource of its assigned
    # short name.
    # 
    # @param [Orange::Resource] resource An instance of Orange::Resource subclass
    # @param [optional, Symbol, String] name A short name to assign as key in Hash 
    #   list of resources.
    #   Doesn't necessarily need to be a symbol, but generally is.
    #   Set to the class name lowercase as a symbol by default.
    def load(resource, name = false)
      name = resource.orange_name if(!name)
      name = resource.class.to_s.gsub(/::/, '_').downcase.to_sym if(!name) 
      @resources[name] = resource.set_orange(self, name)
    end
    
    # Takes an instance of Orange::Middleware::Base subclass and
    # keeps it for later. This way we can provide introspection into the 
    # middleware instances (useful for calling stack_init on them)
    def middleware(middle = false)
      @middleware << middle if middle
      @middleware
    end
    
    # Takes an instance of Orange::Application and saves it. 
    def application(app = false)
      @application = app if app
      @application
    end
    
    # Takes an instance of Orange::Stack and saves it. 
    def stack(stack = false)
      @stack = stack if stack
      @stack
    end
    
    # Convenience self for consistent naming across middleware
    # @return [Orange::Core] self
    def orange;     self;     end
    
    # Registers interest in a callback for a named event.
    #
    # Event registration is stored as a hash list of events and arrays
    # of procs to be executed on each event.
    #
    # @param [Symbol] event the name of the event registered for 
    # @param [optional, Integer] position the position to place the event in,
    #  by default goes to the front of the list. Doesn't necessarily need
    #  to be exact count, empty spaces in array are taken out. Forcing the
    #  event to be at 99 or some such position will typically make sure it 
    #  happens last in the firing process.
    # @param [Block] block The code to be executed upon event firing. 
    #   Saved to an array of procs that are called when #fire is called.
    #   Block must accept one param, which is the intended to be the packet 
    #   causing the block to fire, unless the event happens in setup.
    def register(event, position = 0, &block)
      if block_given?
        if @events[event] 
          @events[event].insert(position, Proc.new)
        else
          @events[event] = Array.new.insert(position, Proc.new)
        end
      end
    end
    
    # Fires a callback for a given packet (or other object)
    # 
    # @param [Symbol] event name of event something has registered for
    # @param [Orange::Packet, object] packet Object, generally Orange::Packet, 
    #   causing the fire. This is passed to each Proc registered.
    # @return [Boolean] returns false if nothing has been registered for the
    #   event, otherwise true.
    def fire(event, packet)
      return false unless @events[event]
      @events[event].compact!
      for callback in @events[event]
        callback.call(packet)
      end
      true
    end
    
    # Returns options of the orange core
    # 
    # @return [Hash] Hash of options
    def options
      @options
    end
    
    
    # Accesses resources array, stored as a hash {:short_name => Resource instance,...}
    # 
    # @param [Symbol] name the short name for the requested resource
    # @param [optional, Boolean] ignore Whether to ignore any calls to resource if not found 
    #   (false is default). This will allow method calls to non-existent resources. Should be
    #   used with caution.
    # @return [Orange::Resource] the resource for the given short name
    def [](name, ignore = false)
      if ignore && !loaded?(name)
        Ignore.new
      else
        @resources[name]
      end 
    end
    
    # Includes module in the Packet class
    # @param [Module] inc module to be included
    def add_pulp(inc)
      self.class.add_pulp inc
    end
    
    # Includes module in this class
    # @param [Module] inc module to be included
    def mixin(inc)
      self.class.mixin inc
    end
    
    # Includes module in this class
    # @param [Module] inc module to be included
    def self.mixin(inc)
      include inc
    end
    
    # Includes module in the Packet class
    # @param [Module] inc module to be included
    def self.add_pulp(inc)
      Packet.mixin inc
    end
  end
end