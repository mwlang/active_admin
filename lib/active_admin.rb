require 'meta_search'

module ActiveAdmin
  
  autoload :VERSION,                  'active_admin/version'
  autoload :Namespace,                'active_admin/namespace'
  autoload :Resource,                 'active_admin/resource'
  autoload :ResourceController,       'active_admin/resource_controller'
  autoload :Dashboards,               'active_admin/dashboards'
  autoload :Renderer,                 'active_admin/renderer'
  autoload :TableBuilder,             'active_admin/table_builder'
  autoload :FormBuilder,              'active_admin/form_builder'
  autoload :TabsRenderer,             'active_admin/tabs_renderer'
  autoload :ViewHelpers,              'active_admin/view_helpers'
  autoload :Breadcrumbs,              'active_admin/breadcrumbs'
  autoload :Filters,                  'active_admin/filters'
  autoload :PageConfig,               'active_admin/page_config'
  autoload :Pages,                    'active_admin/pages'
  autoload :Sidebar,                  'active_admin/sidebar'
  autoload :ActionItems,              'active_admin/action_items'
  autoload :AssetRegistration,        'active_admin/asset_registration'
  autoload :Menu,                     'active_admin/menu'
  autoload :MenuItem,                 'active_admin/menu_item'
  autoload :ActionBuilder,            'active_admin/action_builder'
  autoload :AdminNote,             'active_admin/admin_notes/admin_note'
  autoload :AdminNotesController,  'active_admin/admin_notes/admin_notes_controller'

  extend AssetRegistration

  # The default namespace to put controllers and routes inside. Set this
  # in config/initializers/active_admin.rb using:
  # 
  #   ActiveAdmin.default_namespace = :super_admin
  #
  @@default_namespace = :admin
  mattr_accessor :default_namespace

  # The default number of resources to display on index pages
  @@default_per_page = 30
  mattr_accessor :default_per_page

  # The default sort order for index pages
  @@default_sort_order = 'id_desc'
  mattr_accessor :default_sort_order

  # A hash of all the registered namespaces
  @@namespaces = {}
  mattr_accessor :namespaces

  # The title which get's displayed in the main layout
  @@site_title = ""
  mattr_accessor :site_title

  # Load paths for admin configurations. Add folders to this load path
  # to load up other resources for administration. External gems can
  # include thier paths in this load path to provide active_admin UIs
  @@load_paths = [File.expand_path('app/admin', Rails.root)]
  mattr_accessor :load_paths

  # Stores if everything has been loaded or we need to reload
  @@loaded = false

  # A hash containing a menu for each of our namespaces
  @@menus = {}
  mattr_accessor :menus

  # The class to use to render the tabs in the interface
  @@tabs_renderer = ActiveAdmin::TabsRenderer
  mattr_accessor :tabs_renderer

  # Whether or not to use admin comments
  @@admin_notes = true
  mattr_accessor :admin_notes
  
  # Which method do we use to find the current admin user?
  # By default there is no current admin user
  @@current_admin_user_method = false
  mattr_accessor :current_admin_user_method

  class << self

    # Get's called within the initializer
    def setup
      # Register the default assets
      register_stylesheet 'active_admin.css'
      register_javascript 'active_admin_vendor.js'
      register_javascript 'active_admin.js'

      # Since we're dealing with all our own file loading, we need
      # to remove our paths from the ActiveSupport autoload paths.
      # If not, file nameing becomes very important and can cause clashes.
      ActiveSupport::Dependencies.autoload_paths.reject!{|path| load_paths.include?(path) }

      # Don't eagerload our configs, we'll deal with them ourselves
      Rails.application.config.eager_load_paths = Rails.application.config.eager_load_paths.reject do |path| 
        load_paths.include?(path)
      end

      # Dispatch request which gets triggered once in production
      # and on every require in development mode
      ActionDispatch::Callbacks.to_prepare :active_admin do
        ActiveAdmin.unload!
        # Because every time we load, the routes may have changed
        # we must ensure to load the routes each request (in dev)
        Rails.application.reload_routes!
      end

      yield self
    end

    # Registers a brand new configuration for the given resource.
    #
    # TODO: Setup docs for registration options
    def register(resource, options = {}, &block)
      namespace_name = options[:namespace] == false ? :root : (options[:namespace] || default_namespace)
      namespace = namespaces[namespace_name] ||= Namespace.new(namespace_name)
      namespace.register(resource, options, &block)
    end

    # Returns true if all the configuration files have been loaded.
    def loaded?
      @@loaded
    end

    # Removes all the controllers that were defined by registering
    # resources for administration.
    #
    # We remove them, then load them on each request in development
    # to allow for changes without having to restart the server.
    def unload!
      namespaces.values.each{|namespace| namespace.unload! }
      @@loaded = false
    end

    # Loads all of the ruby files that are within the load path of
    # ActiveAdmin.load_paths. This should load all of the administration
    # UIs so that they are available for the router to proceed.
    #
    # The files are only loaded if we haven't already loaded all the files
    # and they aren't marked for re-loading. To mark the files for re-loading
    # you must first call ActiveAdmin.unload!
    def load!
      unless loaded?
        load_paths.flatten.compact.uniq.each do |path|
          Dir["#{path}/*.rb"].each{|f| load f }
        end
        @@loaded = true
        return true
      end
      false
    end

    # Creates all the necessary routes for the ActiveAdmin configurations
    #
    # Use this within the routes.rb file:
    #
    #   Application.routes.draw do |map|
    #     ActiveAdmin.routes(self)
    #   end
    #
    def routes(router)
      # Ensure that all the configurations (which define the routes)
      # are all loaded
      load!

      # routes for comments controller
      router.instance_eval do
        post "/admin/admin_notes", :to => "active_admin/admin_notes#create", :as => :admin_admin_notes
      end
      
      # Define any necessary dashboard routes
      router.instance_exec(namespaces.values) do |namespaces|
        namespaces.each do |namespace|
          if namespace.root?
            match '/' => 'dashboard#index', :as => 'dashboard'
          else
            name = namespace.name
            match name.to_s => "#{name}/dashboard#index", :as => "#{name.to_s}_dashboard"
          end
        end
      end

      # Now define the routes for each resource
      router.instance_exec(namespaces) do |namespaces|
        resources = namespaces.values.collect{|n| n.resources.values }.flatten
        resources.each do |config|

          # Define the block the will get eval'd within the namespace
          route_definition_block = Proc.new do
            resources config.underscored_resource_name.pluralize do

              # Define any member actions
              member do
                config.member_actions.each do |action|
                  # eg: get :comment
                  send(action.http_verb, action.name)
                end
              end

              # Define any collection actions
              collection do
                config.collection_actions.each do |action|
                  send(action.http_verb, action.name)
                end
              end
            end
          end

          if config.namespace.root?
            instance_eval(&route_definition_block)
          else
            namespace config.namespace.name do
              instance_eval(&route_definition_block)
            end
          end
        end
      end
    end

    #
    # Add before, around and after filters to each registered resource.
    #
    # eg:
    #
    #   ActiveAdmin.before_filter :authenticate_admin!
    #
    def before_filter(*args, &block)
      ResourceController.before_filter(*args, &block)
    end

    def after_filter(*args, &block)
      ResourceController.after_filter(*args, &block)
    end

    def around_filter(*args, &block)
      ResourceController.around_filter(*args, &block)
    end

    # Helper method to add a dashboard section
    def dashboard_section(name, options = {}, &block)
      ActiveAdmin::Dashboards.add_section(name, options, &block)
    end

  end
end
