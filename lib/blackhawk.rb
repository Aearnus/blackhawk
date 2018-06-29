require "blackhawk/version"

module Blackhawk
    class MemoryMatch
        attr_reader(
            :range,
            :match
        )
        
        # Return a string of the memory that was matched.
        #
        # @param encoding [Encoding] the string encoding to use, defaulting to `Encoding::ASCII_8BIT`.
        # @return [String] the string that the matched memory represents.
        def match_string(encoding: Encoding::ASCII_8BIT)
            @match.pack("C*").encode(encoding)
        end
        
        # Creates an instance of the MemoryMatch class.
        #
        # @param range [Array(Fixnum, Fixnum)] the memory range that the match occured at.
        # @param match [Array<Fixnum>] the list of bytes that matched.
        # @return [MemoryMatch] an instance of the MemoryMatch class.
        def initialize(range, match)
            @range = range
            @match = match
        end
    end
    
    class MemoryLens
        attr_reader(
            :loaded_page_range,
            :loaded_page_files,
            :range
        )
        
        # Peer through the MemoryLens and look at the memory it's watching.
        #
        # @raise [NoMemoryError] if more than 2 map files are loaded. this is TODO to fix
        # @return [Array<Fixnum>] the memory that the MemoryLens is looking at.
        def look
            # take the easier path if there's only one page file to load
            if @loaded_page_files.length == 1
                offset = @range[0] - @loaded_page_range[0]
                length = @range[1] - @range[0]
                return @loaded_page_files[0].pread(length, offset).bytes
            # else take the harder path
            elsif @loaded_page_files.length == 2
                offset = @range[0] - @loaded_page_range[0]
                length = @range[1] - @range[0]
                return (@loaded_page_files[0].pread(99999999, offset).bytes << @loaded_page_files[1].read(length - (@loaded_page_range[0][1] - @range[0])))
            else
                raise NoMemoryError.new("MemoryLens cannot currently look at more than 2 map files. Please contact the developer if you actually ran into this in real code and not just a test case.")
            end
        end
        
        # Creates an instance of the MemoryLens class.
        #
        # @param blackhawk [Blackhawk] the blackhawk instance attached to the process.
        # @param range [Array(Fixnum, Fixnum)] the memory range to watch on this object.
        # @raise [RangeError] if the range is outside of the range of the process's memory.
        # @return [MemoryLens] an instance of the MemoryLens class.
        def initialize(blackhawk, range)
            range.sort!
            map_ranges_memo = blackhawk.map_ranges
            raise RangeError.new("MemoryLens range underflow") if range[0] < map_ranges_memo[0][0] 
            raise RangeError.new("MemoryLens range overflow") if range[1] < map_ranges_memo[-1][1] 
            
            # reject every map range that's completely below or completely above the wanted range
            ranges_to_load = map_ranges_memo.
                reject { |map_range| map_range[1] < range[0] }.
                reject { |map_range| map_range[0] > range[1] }
            
            @loaded_page_range = [ranges_to_load[0][0], ranges_to_load[-1][1]]    
            
            @loaded_page_files = ranges_to_load.
                map { |range_to_load| Kernel.open(blackhawk.map_range_to_map_path(range_to_load), "rb") }
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
        def map_range_to_map_path(map_range)
            File.join self.path, "map_files", "#{map_range[0]-map_range[1]}"
        end
        
        # @return [Array<Array(Fixnum,Fixnum)>] a list of memory address ranges of the attached process for which map files exist
        # @note this is guaranteed to be in order
        def map_ranges
            self.
                map_paths.
                map { |map_path| map_path_to_map_range(map_path) }.
                sort_by { |range| range[0] }
        end
        
        # @!endgroup
        
        # @!group Memory searching and watching
        
        # test invocation: 
        # b = Blackhawk::Blackhawk.new 1; b.search_byte_list([1,2,3], debug:true)
        
        # Search memory using a provided equality block.
        # @see search_byte_list Example usage
        #
        # @param length [Array<Fixnum>] the length of bytes to search process memory for.
        # @yieldparam byte_list [Array<Fixnum>] the list of bytes to compare
        # @yieldreturn [Boolean] whether or not that list of bytes produces a match
        # @param range [Array(Fixnum, Fixnum)] if you want to search through a range of memory. 
        # @param range [nil] if you want to search the entire process memory.
        # @param verbose [Boolean] whether or not to print out progress.
        # @param debug [Boolean] whether or not to print debug information.
        # @raise [RangeError] if a byte less than 0 or larger than 255 is provided.
        # @raise [NoMemoryError] if the byte list is longer than a usual map size (1MB).
        # @return [nil] if no match was found.
        # @return [Array<MemoryMatch>] if a match was found.
        def search_yield(length, range: nil, verbose: false, debug: false)
            verbose = true if debug
            raise NoMemoryError.new("Can't search for a byte list larger than the 1MB page size") if length > (1024 * 1024)
            #raise RangeError.new("Byte out of range") if list.any? { |byte| (byte < 0) || (byte > 255) }
            
            map_paths_memo = self.map_paths
            out = []
            
            map_paths_memo.each_with_index do |map_path, map_index|
                map_range = map_path_to_map_range map_path
                
                if verbose
                    puts "Searching map #{map_range.first.to_s 16} - #{map_range.last.to_s 16} [#{(100 * map_index.to_f / map_paths_memo.length.to_f).round 1}%]..."
                end
                
                map_bytestring = IO.binread(map_path)
                
                if map_index == 0
                    previous_map_file = nil
                    previous_map_bytestring = "" 
                else 
                    previous_map_file = Kernel.open(map_paths_memo[map_index - 1], "rb")
                    previous_map_file.seek(-length, IO::SEEK_END)
                    previous_map_bytestring = previous_map_file.read
                    previous_map_file.close
                end
                if map_index == map_paths_memo.length - 1
                    next_map_file = nil
                    next_map_bytestring = ""
                else
                    next_map_file = Kernel.open(map_paths_memo[map_index + 1], "rb")
                    next_map_bytestring = next_map_file.read length
                    next_map_file.close
                end
                
                # this string is key. this is the string we're going to search for to find the
                # provided byte list
                map_bytestring_overhang = 
                    previous_map_bytestring +
                    map_bytestring +
                    next_map_bytestring
                if debug
                    puts "    PREVIOUS_MAP: #{previous_map_bytestring.encoding} #{previous_map_bytestring.length}"
                    puts "    MAP_BYTESTRING: #{map_bytestring_overhang.encoding} #{map_bytestring_overhang.length}"
                    puts "    NEXT_MAP: #{next_map_bytestring.encoding} #{next_map_bytestring.length}"
                end
                
                # finally, search the memory
                map_bytestring_overhang.bytes.each_cons(length).with_index do |byte_list, overhang_offset|
                    offset = map_range.first + (overhang_offset - length)
                    if (yield byte_list)
                        puts "FOUND A MATCH @ #{offset.to_s 16}"
                        out << MemoryMatch.new([offset, offset + length], byte_list)
                    end
                end
            end
            return out
        end
        
        # Searches the entire memory for a specified list of bytes.
        #
        # @param list [Array<Fixnum>] the bytes to search the process memory for.
        # @param range [Array(Fixnum, Fixnum)] if you want to search through a range of memory. 
        # @param range [nil] if you want to search the entire process memory.
        # @param verbose [Boolean] whether or not to print out progress.
        # @param debug [Boolean] whether or not to print debug information.
        # @raise [RangeError] if a byte less than 0 or larger than 255 is provided.
        # @raise [NoMemoryError] if the byte list is longer than a usual map size (1MB).
        # @return [nil] if no match was found.
        # @return [Array<MemoryMatch>] if a match was found.
        def search_byte_list(list, range: nil, verbose: false, debug: false)
            raise NoMemoryError.new("Can't search for a byte list larger than the 1MB page size") if list.length > (1024 * 1024)
            raise RangeError.new("Byte out of range") if list.any? { |byte| (byte < 0) || (byte > 255) }
            return self.search_yield(list.length, range: range, verbose: verbose, debug: debug) { |byte_list| 
                byte_list == list
            }
        end
        
        # Searches the entire memory for a specified string.
        #
        # @see search_byte_string the function that is used internally for the search.
        # @param string [String] the string to search the process memory for.
        # @param encoding [Encoding] the string encoding to use in the search, defaulting to `Encoding::ASCII_8BIT`.
        # @param verbose [Boolean] whether or not to print out progress.
        # @param debug [Boolean] whether or not to print debug information.
        # @raise [NoMemoryError] if the string is larger than 1MB.
        # @return [nil] if no match was found.
        # @return [Array<MemoryMatch>] if a match was found.
        def search_string(string, range: nil, encoding: Encoding::ASCII_8BIT, verbose: false, debug: false)
            list = string.encode(encoding).bytes
            return self.search_yield(list, range: range, verbose: verbose, debug: debug) { |byte_list| 
                byte_list == list
            }
        end
        
        # Allows the user to watch an area of memory associated with a previously found match.
        #
        # @param match [MemoryMatch] the successful memory match.
        # @return [MemoryLens] an object used to watch that area of memory.
        def watch_match(match)
            return MemoryLens.new(match.range)
        end
        
        # Allows the user to watch an area of memory.
        #
        # @param range [Array<Fixnum>] the range of memory to watch.
        # @raise [IOError] the range of memory to watch is outside of the bounds of the attached process's mapped memory.
        # @return [MemoryLens] an object used to watch that area of memory.
        def watch_range(range)
            return MemoryLens.new(match.range)
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