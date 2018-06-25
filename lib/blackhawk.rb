require "blackhawk/version"

#module Blackhawk
  # Your code goes here...
#end

class Blackhawk
    def path
        File.join "/proc", "#{@pid}"
    end
    def maps
        Dir["#{File.join self.path, "map_files", "*"}"]
    end
    
    def initialize(pid)
        raise PermissionError.new("Blackhawk requires superuser permissions") unless Process.uid == 0
        @pid = pid
    end
end