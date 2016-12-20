module Synthea
  module Generic
    class Package
      attr_reader :name, :modules, :main

      def initialize(package_path)
        @name = package_path[%r{\/(\w+)\/*$}, 1]
        @modules = []
        @main = {}

        files = Dir.glob(File.join(package_path, '*.json'))
        main_file = File.join(package_path, @name + '.json')
        # The package must include a JSON module file with the same name.
        # That file is the "main" file for the package and its context is
        # run first.
        unless files.include?(main_file)
          raise "No main module \"#{@name}.json\" found in package \"#{@name}\""
        end

        files.each do |file|
          m = load_module(file)
          unless m['package'] && m['package'] == @name
            raise "Module \"#{m['name']}\" must be part of package \"#{@name}\""
          end
          @main = m if file == main_file
          @modules << m
        end
      end

      def load_module(file)
        m = JSON.parse(File.read(file))
        puts "Loaded \"#{m['name']}\" module from package \"#{@name}\""
        m
      end
    end
  end
end
