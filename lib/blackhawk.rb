require "blackhawk/version"

module Blackhawk
    class MemoryMatch
        attr_accessor(
            :range,
            :match
        )
    end
    
    class MemoryLens
    end
    
    class Blackhawk
        
        # @!group Linux IO 
        
        # @return [String] the path to the attached process in the `/proc` folder
        def path
            File.join "/proc", "#{@pid}"
        end
        
        # @return [Array<String>] a list of paths to the memory map files of the attached process
        def maps
            Dir["#{File.join self.path, "map_files", "*"}"]
        end
        
        # @return [Array<Array(Fixnum,Fixnum)>] a list of memory address ranges of the attached process for which map files exist
        def map_ranges
            self.
                maps.
                map { |file| File.split(file).last }.
                map { |range_string| range_string.scan(/[0-9a-f]+/i).map { |range| range.to_i 16 } }
        end
        
        # @!endgroup
        
        # @!group Memory searching and watching
        
        # Searches the entire memory for a specified list of bytes.
        #
        # @param list [Array<Fixnum>] the bytes to search the process memory for.
        # @raise [RangeError] if a byte less than 0 or larger than 255 is provided.
        # @return [nil] if no match was found.
        # @return [MemoryMatch] if a match was found.
        def search_byte_list(list)
        end
        
        # Searches the entire memory for a specified string.
        #
        # @param string [String] the string to search the process memory for.
        # @param encoding [Encoding] the string encoding to use in the search, defaulting to `Encoding::US_ASCII`.
        # @return [nil] if no match was found.
        # @return [MemoryMatch] if a match was found.
        def search_string(string, encoding: Encoding::US_ASCII)
        end
        
        # Allows the user to watch an area of memory associated with a previously found match.
        #
        # @param match [MemoryMatch] the successful memory match.
        # @return [MemoryLens] an object used to watch that area of memory.
        def watch_match(match)
        end
        
        # Allows the user to watch an area of memory.
        #
        # @param range [Array<Fixnum>] the range of memory to watch.
        # @raise [IOError] the range of memory to watch is outside of the bounds of the attached process's mapped memory.
        # @return [MemoryLens] an object used to watch that area of memory.
        def watch_range(range)
        end
        
        # @!endgroup
        
        # Creates an instance of the Blackhawk class.
        #
        # @param pid [Fixnum] the PID of the process to attach to.
        # @raise [IOError] if superuser permissions were not provided.
        # @return [Blackhawk] an instance of the Blackhawk class.
        def initialize(pid)
            raise IOError.new("Blackhawk requires superuser permissions") unless Process.uid == 0
            @pid = pid
        end
    end
end