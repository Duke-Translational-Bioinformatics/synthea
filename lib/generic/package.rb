module Synthea
  module Generic
    class Package
      attr_reader :name, :main, :submodules

      def initialize(package_path)
        @path = package_path
        @name = get_name(package_path)

        files = Dir.glob(get_path('*.json'))
        main_file = get_path(@name + '.json')
        # The package must include a JSON module file with the same name.
        # That file is the "main" file for the package and its context is
        # run first.
        unless files.include?(main_file)
          raise "No main module \"#{@name}.json\" found in package \"#{@name}\""
        end

        files.each do |filename|
          context = get_context(filename)
          unless context.package && context.package == @name
            raise "Module \"#{context.name}\" must be part of package \"#{@name}\""
          end
          if filename == main_file
            @main = context
          else
            @submodules ||= {}
            @submodules[context.name] = context
          end
        end
      end

      def get_context(fullpath)
        context = Synthea::Generic::Context.new(get_config(fullpath))
        puts "Loaded \"#{context.name}\" module from package \"#{@name}\""
        context
      end

      def get_config(fullpath)
        JSON.parse(File.read(fullpath))
      end

      def get_path(filename)
        File.join(@path, filename)
      end

      def get_name(package_path)
        package_path[%r{\/(\w+)\/*$}, 1]
      end
    end
  end
end
