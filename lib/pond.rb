require 'monitor'

require 'pond/version'

class Pond
  class Timeout < StandardError; end

  attr_reader :allocated, :available, :timeout, :collection, :maximum_size

  def initialize(options = {}, &block)
    @block   = block
    @monitor = Monitor.new
    @cv      = Monitor::ConditionVariable.new(@monitor)

    maximum_size = options[:maximum_size] || 10

    @allocated = {}
    @available = Array.new(options[:eager] ? maximum_size : 0, &block)

    self.timeout      = options[:timeout]    || 1
    self.collection   = options[:collection] || :queue
    self.maximum_size = maximum_size
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

  def timeout=(timeout)
    raise "Bad value for Pond timeout: #{timeout.inspect}" unless Numeric === timeout && timeout >= 0
    sync { @timeout = timeout }
  end

  def collection=(type)
    raise "Bad value for Pond collection: #{type.inspect}" unless [:stack, :queue].include?(type)
    sync { @collection = type }
  end

  def maximum_size=(max)
    raise "Bad value for Pond maximum_size: #{max.inspect}" unless Integer === max && max >= 0
    sync do
      @maximum_size = max
      {} until size <= max || pop_object.nil?
    end
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
      object = @allocated.delete(Thread.current)

      if object && object != @block && size < maximum_size
        @available << object
        @cv.signal
      end
    end
  end

  def get_object(timeout)
    pop_object || size < maximum_size && @block || @cv.wait(timeout) && false
  end

  def pop_object
    case collection
    when :queue then @available.shift
    when :stack then @available.pop
    end
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

  class << self
    def wrap(*args, &block)
      Wrapper.new(*args, &block)
    end
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
