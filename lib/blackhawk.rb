require "blackhawk/version"

module Blackhawk
class Blackhawk
    def path
        File.join "/proc", "#{@pid}"
    end
    def maps
        Dir["#{File.join self.path, "map_files", "*"}"]
    end
    def map_ranges
        self.
            maps.
            map{ |file| File.split(map).last }.
            map{ |range_string| range_string.scan(/[0-9a-f]+/i).map{ |range| range.to_i 16 } }
    end
        
    def initialize(pid)
        raise IOError.new("Blackhawk requires superuser permissions") unless Process.uid == 0
        @pid = pid
    end
end
end