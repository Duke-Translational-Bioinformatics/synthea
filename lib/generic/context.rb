module Synthea
  module Generic
    class Context
      attr_reader :config, :name, :package
      attr_accessor :history, :current_state, :args

      def initialize(config)
        @config = config
        @name = @config['name']
        @package = @config['package']
        @history = []
        @current_state = create_state('Initial')
        # For use by submodules:
        @args = {}
      end

      def run(time, entity)
        # if @current_state.run returns true, it means we should progress to the next state
        while @current_state.run(time, entity)
          next_state = self.next(time, entity)

          if @current_state.name == next_state
            # looped from a state back to itself, so for perf reasons (memory usage)
            # just stay in the same state and change the dates instead of keeping another object

            exited = @current_state.exited

            @current_state.start_time = exited
            @current_state.exited = nil

            if exited < time
              # This must be a delay state that expired between cycles, so temporarily rewind time
              blocking_state = run(exited, entity)
              return blocking_state if blocking_state.alters_active_context?
            end
          else
            # The history of CallSubmodule states is managed by the ContextRunner
            @history << @current_state unless @current_state.is_a?(Synthea::Generic::States::CallSubmodule)
            @current_state = create_state(next_state)
            if @history.last.exited < time
              # This must be a delay state that expired between cycles, so temporarily rewind time
              blocking_state = run(@history.last.exited, entity)
              return blocking_state if blocking_state.alters_active_context?
            end
          end
        end
        # Once execution blocks, return the state that blocked it
        @current_state
      end

      def next(time, entity)
        transition = @current_state.transition
        return nil unless transition
        # no defined transition

        transition.follow(self, entity, time)
      end

      def most_recent_by_name(name)
        @history.reverse.find { |h| h.name == name }
      end

      def state_config(name)
        @config['states'][name]
      end

      def all_states
        @config['states'].keys
      end

      def create_state(name)
        return States::Terminal.new(self, 'Terminal') if name.nil?

        clazz = state_config(name)['type']
        Object.const_get("Synthea::Generic::States::#{clazz}").new(self, name)
      end

      def validate
        messages = []

        reachable = ['Initial']

        all_states.each do |state_name|
          state = create_state(state_name)
          messages.push(*state.validate(self, []))

          reachable.push(*state.transition.all_transitions) if state.transition && state.transition.all_transitions != []
        end

        unreachable = all_states - reachable
        unreachable.each { |st| messages << "State '#{st}' is unreachable" }

        messages.uniq
      end

      def inspect
        "#<Synthea::Generic::Context::#{object_id}> #{@current_state.name}"
      end
    end
  end
end
