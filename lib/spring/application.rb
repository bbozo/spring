require "spring/configuration"
require "spring/application_watcher"
require "spring/commands"
require "set"

module Spring
  class << self
    attr_accessor :application_watcher
  end

  self.application_watcher = ApplicationWatcher.new

  class Application
    WATCH_INTERVAL = 0.2

    attr_reader :manager, :watcher

    def initialize(manager, watcher = Spring.application_watcher)
      @manager = manager
      @watcher = watcher
      @setup   = Set.new
    end

    def start
      require Spring.application_root_path.join("config", "application")

      # The test environment has config.cache_classes = true set by default.
      # However, we don't want this to prevent us from performing class reloading,
      # so this gets around that.
      Rails::Application.initializer :initialize_dependency_mechanism, group: :all do
        ActiveSupport::Dependencies.mechanism = :load
      end

      require Spring.application_root_path.join("config", "environment")

      watcher.add_files $LOADED_FEATURES
      watcher.add_files ["Gemfile", "Gemfile.lock"].map { |f| "#{Rails.root}/#{f}" }
      watcher.add_globs Rails.application.paths["config/initializers"].map { |p| "#{Rails.root}/#{p}/*.rb" }

      run
    end

    def run
      loop do
        watch_application
        serve manager.recv_io(UNIXSocket)
      end
    end

    def watch_application
      until IO.select([manager], [], [], WATCH_INTERVAL)
        exit if watcher.stale?
      end
    end

    def serve(client)
      streams     = 3.times.map { client.recv_io }
      args_length = client.gets.to_i
      args        = args_length.times.map { client.read(client.gets.to_i) }
      command     = Spring.command(args.shift)

      setup command

      ActionDispatch::Reloader.cleanup!
      ActionDispatch::Reloader.prepare!

      pid = fork {
        Process.setsid
        [STDOUT, STDERR, STDIN].zip(streams).each { |a, b| a.reopen(b) }
        IGNORE_SIGNALS.each { |sig| trap(sig, "DEFAULT") }
        invoke_after_fork_callbacks
        command.call(args)
      }

      manager.puts pid

      # Wait in a separate thread so we can run multiple commands at once
      Thread.new {
        _, status = Process.wait2 pid
        streams.each(&:close)
        client.puts(status.exitstatus)
        client.close
      }

    rescue => e
      streams.each(&:close) if streams
      client.puts(1)
      client.close
      raise
    end

    # The command might need to require some files in the
    # main process so that they are cached. For example a test command wants to
    # load the helper file once and have it cached.
    #
    # FIXME: The watcher.add_files will reset the watcher, which may mean that
    #        previous changes to already-loaded files are missed.
    def setup(command)
      return if @setup.include?(command.class)
      @setup << command.class

      if command.respond_to?(:setup)
        command.setup
        watcher.add_files $LOADED_FEATURES # loaded features may have changed
      end
    end

    def invoke_after_fork_callbacks
      Spring.after_fork_callbacks.each do |callback|
        callback.call
      end
    end
  end
end
