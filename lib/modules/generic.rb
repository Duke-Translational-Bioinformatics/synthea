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
          puts "Loading package #{dir}..."
          @gmodules << Synthea::Generic::Package.new(dir)
        end

        # load standalone modules
        Dir.glob(File.join(module_dir, '*.json')).each do |file|
          @gmodules << load_module(file)
        end
      end

      def load_module(file)
        m = JSON.parse(File.read(file))
        puts "Loaded \"#{m['name']}\" module from #{file}"
        m
      end

      # this rule loops through the generic modules, processing one at a time
      rule :generic, [:generic], [:generic, :death] do |time, entity|
        return unless entity.alive?(time)

        entity[:generic] ||= {}
        @gmodules.each do |m|
          context = if m.is_a?(Synthea::Generic::Package)
                      Synthea::Generic::Context.new(m.main)
                    else
                      Synthea::Generic::Context.new(m)
                    end
          entity[:generic][context.name] ||= context
          entity[:generic][context.name].run(time, entity)
        end
      end

      #-----------------------------------------------------------------------#

      def self.log_modules(entity)
        if entity && Synthea::Config.generic.log
          entity[:generic].each do |_key, context|
            context.log_history if context.logged.nil?
          end
        end
      end

      def self.perform_wellness_encounter(entity, time)
        return if entity[:generic].nil?

        # find all of the generic modules that are currently waiting for a wellness encounter
        entity[:generic].each do |_name, ctx|
          st = ctx.current_state
          next unless st.is_a?(Synthea::Generic::States::Encounter) && st.wellness && !st.processed
          st.perform_encounter(time, entity, false)
          # The encounter got unjammed -- progress through the subsequent states
          ctx.run(time, entity)
        end
      end
    end
  end
end
