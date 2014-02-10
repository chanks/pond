require 'monitor'

require 'pond/version'

class Pond
  class Timeout < StandardError; end

  attr_reader :allocated, :available

  def self.wrap(*args, &block)
    Wrapper.new(new(*args, &block))
  end

  def initialize(options = {}, &block)
    @timeout    = options[:timeout]      || 1.0
    @max_size   = options[:maximum_size] || 10
    @collection = options[:collection]   || :queue

    @block   = block
    @monitor = Monitor.new
    @cv      = Monitor::ConditionVariable.new(@monitor)

    @available = []
    @allocated = {}
  end

  def checkout(&block)
    if object = sync { @allocated[Thread.current] }
      yield object
    else
      _checkout(&block)
    end
  end

  def size
    sync { @available.size + @allocated.size }
  end

  private

  def _checkout
    object   = nil
    deadline = Time.now + @timeout

    loop do
      time_left = deadline - Time.now
      raise Timeout if time_left < 0

      sync do
        if @available.empty?
          if size >= @max_size
            @cv.wait(time_left)
          else
            object = @block
          end
        else
          if @collection == :queue
            object = @available.shift
          elsif @collection == :stack
            object = @available.pop
          end
        end

        @allocated[Thread.current] = object if object
      end

      break if object
    end

    if object == @block
      object = @block.call
      sync { @allocated[Thread.current] = object }
    end

    yield object
  ensure
    if object
      sync do
        @allocated.delete(Thread.current)
        @available << object unless object == @block
        @cv.signal
      end
    end
  end

  def sync(&block)
    @monitor.synchronize(&block)
  end

  class Wrapper < BasicObject
    attr_reader :pond

    def initialize(pond)
      @pond = pond
    end

    def method_missing(*args, &block)
      @pond.checkout { |object| object.send(*args, &block) }
    end
  end
end
