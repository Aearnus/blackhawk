require "blackhawk/version"

module Blackhawk
  # Your code goes here...
end

class Blackhawk
    def path
        "/proc/#{@pid}"
    end
    def new(pid)
        raise PermissionError.new("Blackhawk requires superuser permissions") unless Process.uid == 0
        @pid = pid

    end
end
