module Synthea
  module Modules
    class Generic < Synthea::Rules
      def initialize
        super
        # load all the JSON module files in lib/generic/modules/. If it's a
        # directory, treat as a package of submodules.
        @gmodules = []
        module_dir = File.expand_path('../../generic/modules', __FILE__)

        # load packages
        packages = Dir.glob(File.join(module_dir, '*')).select { |f| File.directory? f }
        packages.each do |dir|
          new_package = Synthea::Generic::Package.new(dir)
          @gmodules << new_package
          puts "Loaded package \"#{new_package.name}\""
        end

        # load standalone modules
        Dir.glob(File.join(module_dir, '*.json')).each do |file|
          @gmodules << load_module(file)
        end
      end

      def load_module(file)
        cfg = JSON.parse(File.read(file))
        puts "Loaded \"#{cfg['name']}\" module from #{file}"
        cfg
      end

      # this rule loops through the generic modules, processing one at a time
      rule :generic, [:generic], [:generic, :death] do |time, entity|
        return unless entity.alive?(time)

        entity[:generic] ||= {}
        @gmodules.each do |cfg|
          name = if cfg.is_a?(Synthea::Generic::Package)
                   cfg.name
                 else
                   cfg['name']
                 end
          # For each entity we initialize a new runner from each config
          entity[:generic][name] ||= Synthea::Generic::ContextRunner.new(cfg)
          entity[:generic][name].run(time, entity)
        end
      end

      #-----------------------------------------------------------------------#

      def self.log_modules(entity)
        if entity && Synthea::Config.generic.log
          entity[:generic].each do |_key, runner|
            runner.log_history if runner.logged.nil?
          end
        end
      end

      def self.perform_wellness_encounter(entity, time)
        return if entity[:generic].nil?

        # find all of the generic modules that are currently waiting for a wellness encounter
        entity[:generic].each do |_key, runner|
          next unless runner.active?

          st = runner.active_context.current_state
          next unless st.is_a?(Synthea::Generic::States::Encounter) && st.wellness && !st.processed
          st.perform_encounter(time, entity, false)
          # The encounter got unjammed -- progress through the subsequent states
          runner.run(time, entity)
        end
      end
    end
  end
end
