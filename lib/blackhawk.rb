require "blackhawk/version"

module Blackhawk
    class MemoryMatch
        attr_accessor(
            :range,
            :match
        )
    end
    
    class MemoryLens
        def read
        end
        
        def initialize(range)
        end
    end
    
    class Blackhawk
        
        # @!group Linux IO 
        
        # @return [String] the path to the attached process in the `/proc` folder
        def path
            File.join "/proc", "#{@pid}"
        end
        
        # @return [Array<String>] a list of paths to the memory map files of the attached process
        def map_paths
            Dir["#{File.join self.path, "map_files", "*"}"]
        end
        
        def map_path_to_map_range(map_path)
            File.split(map_path).
                last.
                scan(/[0-9a-f]+/i).
                map { |range| range.to_i 16 }
        end
        
        # @return [Array<Array(Fixnum,Fixnum)>] a list of memory address ranges of the attached process for which map files exist
        def map_ranges
            self.
                map_paths.
                map { |map_path| map_path_to_map_range(map_path) }
        end
        
        # @!endgroup
        
        # @!group Memory searching and watching
        
        # Searches the entire memory for a specified list of bytes.
        #
        # @param list [Array<Fixnum>] the bytes to search the process memory for.
        # @param range [Array(Fixnum, Fixnum)] if you want to search through a range of memory. 
        # @param range [nil] if you want to search the entire process memory.
        # @param verbose [Boolean] whether or not to print out progress.
        # @raise [RangeError] if a byte less than 0 or larger than 255 is provided.
        # @raise [NoMemoryError] if the byte list is longer than the map size (1MB).
        # @return [nil] if no match was found.
        # @return [MemoryMatch] if a match was found.
        def search_byte_list(list, range: nil, verbose: false)
            raise NoMemoryError.new("Can't search for a byte list larger than the 1MB page size") if list.length > (1024 * 1024)
            raise RangeError.new("Byte out of range") if list.any? { |byte| (byte < 0) || (byte > 255) }
            
            map_paths_memo = self.map_paths
            
            map_paths_memo.each_with_index do |map_path, map_index|
                map_range = map_path_to_map_range(map_path)
                
                if verbose
                    puts "Searching map #{map_range.first.to_s 16} - #{map_range.last.to_s 16} [#{(100 * map_index.to_f / map_paths_memo.length.to_f).round 1}%]..."
                end
                
                map_bytestring = IO.binread(map_path)
                
                if map_index == 0
                    previous_map_file = nil
                else 
                    previous_map_file = Kernel.open(map_paths_memo[map_index - 1], "rb")
                    previous_map_file.seek(-list.length, IO::SEEK_END)
                    previous_map_bytestring = previous_map_file.read
                    previous_map_file.close
                end
                if map_index == map_paths_memo.length - 1
                    next_map_file = nil
                else
                    next_map_file = Kernel.open(map_paths_memo[map_index + 1], "rb")
                    next_map_bytestring = next_map_file.read list.length
                    next_map_file.close
                end
                
                map_bytestring_overhang = 
                    (previous_map_file.nil? ? "" : previous_map_bytestring) +
                    map_bytestring +
                    (next_map_file.nil? ? "" : next_map_bytestring)
                    
                if verbose
                    puts "    PREVIOUS_MAP: #{(previous_map_file.nil? ? "" : previous_map_bytestring).encoding} #{(previous_map_file.nil? ? "" : previous_map_bytestring).length}"
                    puts "    MAP_BYTESTRING: #{map_bytestring_overhang.encoding} #{map_bytestring_overhang.length}"
                    puts "    NEXT_MAP: #{(next_map_file.nil? ? "" : next_map_bytestring).encoding} #{(next_map_file.nil? ? "" : next_map_bytestring).length}"
                end
            end
        end
        
        # Searches the entire memory for a specified string.
        #
        # @param string [String] the string to search the process memory for.
        # @param encoding [Encoding] the string encoding to use in the search, defaulting to `Encoding::US_ASCII`.
        # @return [nil] if no match was found.
        # @return [MemoryMatch] if a match was found.
        def search_string(string, range: nil, encoding: Encoding::US_ASCII)
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