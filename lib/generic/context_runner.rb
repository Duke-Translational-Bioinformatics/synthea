module Synthea
  module Generic
    class ContextRunner
      attr_reader :name, :stack, :package, :history, :logged

      def initialize(config)
        @stack = []
        @history = []

        # When the runner is initialized we push the first context onto the stack
        if config.is_a?(Synthea::Generic::Package)
          @package = config
          @stack.push(Synthea::Generic::Context.new(@package.main))
          @name = @package.name
        else
          @stack.push(Synthea::Generic::Context.new(config))
          @name = config['name']
        end
      end

      def run(time, entity)
        unless active?
          if Synthea::Config.generic.log && @logged.nil?
            log_history
            @logged = true
          end
          return
        end
        # Always run the module that's on the top of the stack (active)
        blocking_state = active_context.run(time, entity)
        if blocking_state.is_a?(Synthea::Generic::States::Terminal)
          # Pop this context off the stack, and attempt to run the next
          # level of the stack. If this is the last context on the stack
          # we're done executing this module or package.
          blocking_state.exited = time
          popped = stack.pop
          popped.history << blocking_state

          # If there is still a running context, update it's history with the latest history
          # from the submodule. When a submodule returns it always has the most up-to-date history.
          if active?
            active_context.history = popped.history
          else
            # The last context has been run, the history is complete
            @history = popped.history
          end
          run(time, entity)

        elsif blocking_state.is_a?(Synthea::Generic::States::CallSubmodule)
          active_context.history << blocking_state
          # Must be a name of a submodule, not the name of the file it's in
          submodule = blocking_state.submodule
          # The submodule must exist to call it
          raise "Cannot find submodule \"#{submodule}\" in package \"#{@package.name}\"" unless @package.submodules.key?(submodule)
          context = Synthea::Generic::Context.new(@package.submodules[submodule])
          # Seed it's history with the latest history.
          context.history = active_context.history
          context.args = blocking_state.args
          # push the submodule's context onto the stack and resume execution.
          @stack.push(context)
          run(time, entity)
        end
      end

      def active_context
        # Return the context that is currently active (being processed)
        stack.last
      end

      def active?
        # Returns true if the module is still active (not done processing)
        !active_context.nil?
      end

      def history
        if active?
          # If active, the most up-to-date history is actually in the running context.
          active_context.history
        else
          @history
        end
      end

      def log_history
        puts '/==============================================================================='
        puts "| #{@name} Log"
        puts '|==============================================================================='
        puts '| Entered                   | Exited                    | State'
        puts '|---------------------------|---------------------------|-----------------------'
        history.each do |h|
          log_state(h)
        end
        puts '\\==============================================================================='
      end

      def log_state(state)
        exit_str = state.exited ? state.exited.strftime('%FT%T%:z') : '                         '
        puts "| #{state.entered.strftime('%FT%T%:z')} | #{exit_str} | #{state.name}"
      end
    end
  end
end
