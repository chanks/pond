require 'monitor'

require 'pond/version'

class Pond
  class Timeout < StandardError; end

  attr_reader :allocated, :available

  def self.wrap(*args, &block)
    Wrapper.new(*args, &block)
  end

  def initialize(options = {}, &block)
    @timeout    = options[:timeout]      || 1.0
    @max_size   = options[:maximum_size] || 10
    @collection = options[:collection]   || :queue

    @block   = block
    @monitor = Monitor.new
    @cv      = Monitor::ConditionVariable.new(@monitor)

    @available = Array.new(options[:eager] ? @max_size : 0, &block)
    @allocated = {}
  end

  def checkout(&block)
    if object = current_object
      yield object
    else
      checkout_object(&block)
    end
  end

  def size
    sync { @available.size + @allocated.size }
  end

  private

  def checkout_object
    lock_object
    yield current_object
  ensure
    unlock_object
  end

  def lock_object
    deadline = Time.now + @timeout

    until current_object
      raise Timeout if (time_left = deadline - Time.now) < 0

      sync do
        if object = get_object(time_left)
          set_current_object(object)
        end
      end
    end

    # We need to protect changes to @allocated and @available with the monitor
    # so that #size always returns the correct value. But, we don't want to
    # call the instantiation block while we have the lock, since it may take a
    # long time to return. So, we set the checked-out object to the block as a
    # signal that it needs to be called.
    set_current_object(@block.call) if current_object == @block
  end

  def unlock_object
    sync do
      if object = @allocated.delete(Thread.current) and object != @block
        @available << object
        @cv.signal
      end
    end
  end

  def get_object(timeout)
    pop_object || below_capacity? && @block || @cv.wait(timeout) && false
  end

  def pop_object
    case @collection
      when :queue then @available.shift
      when :stack then @available.pop
      else raise "Bad value for Pond collection: #{@collection.inspect}"
    end
  end

  def below_capacity?
    size < @max_size
  end

  def current_object
    sync { @allocated[Thread.current] }
  end

  def set_current_object(object)
    sync { @allocated[Thread.current] = object }
  end

  def sync(&block)
    @monitor.synchronize(&block)
  end

  class Wrapper < BasicObject
    attr_reader :pond

    def initialize(*args, &block)
      @pond = ::Pond.new(*args, &block)
    end

    def method_missing(*args, &block)
      @pond.checkout { |object| object.send(*args, &block) }
    end
  end
end
