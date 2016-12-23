module Synthea
  module Generic
    class ContextRunner
      attr_reader :name, :stack, :package, :history, :logged

      def initialize(context)
        @stack = []
        @history = []
        @name = context.name

        if context.is_a?(Synthea::Generic::Package)
          @package = context
          @stack.push(@package.main)
        else
          @stack.push(context)
        end
      end

      def run(time, entity)
        if stack.empty?
          if Synthea::Config.generic.log && @logged.nil?
            log_history
            @logged = true
          end
          return
        end
        # Always run the module that's on the top of the stack
        blocking_state = stack.last.run(time, entity)

        if blocking_state.is_a?(Synthea::Generic::States::Terminal)
          # Pop this context off the stack, and attempt to run the next
          # level of the stack. If this is the last context on the stack
          # we're done executing this module or package.
          blocking_state.exited = time
          context = stack.pop
          # The context started with the history up to and including the
          # CallSubmodule. Any history written by the submodules was appended
          # to this history. When a submodule returns it therefore has the most
          # up-to-date history.
          context.history << blocking_state
          # If there is still a running context, update it's history
          # with the latest history from the submodule.
          if active_context.nil?
            # The last context has been run, the history is complete
            @history = context.history
          else
            active_context.history = context.history
          end
          run(time, entity)

        elsif blocking_state.is_a?(Synthea::Generic::States::CallSubmodule)
          active_context.history << blocking_state
          # Take a snapshot of the current history
          @history = active_context.history
          # Must be a name of a submodule, not the name of the file it's in
          submodule = blocking_state.submodule
          # The submodule must exist to call it
          raise "Cannot find submodule \"#{submodule}\" in package \"#{@package.name}\"" unless @package.submodules.key?(submodule)
          context = @package.submodules[submodule]
          # Seed it's history with the latest history from its parent module.
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

      def log_history
        puts '/==============================================================================='
        puts "| #{@name} Log"
        puts '|==============================================================================='
        puts '| Entered                   | Exited                    | State'
        puts '|---------------------------|---------------------------|-----------------------'
        @history.each do |h|
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
