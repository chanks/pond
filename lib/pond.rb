# frozen_string_literal: true

require 'monitor'

require 'pond/version'

class Pond
  class Timeout < StandardError; end

  attr_reader :allocated, :available, :timeout, :collection, :maximum_size, :detach_if

  DEFAULT_DETACH_IF = lambda { |_| false }

  def initialize(
    maximum_size: 10,
    eager: false,
    timeout: 1,
    collection: :queue,
    detach_if: DEFAULT_DETACH_IF,
    &block
  )
    @block   = block
    @monitor = Monitor.new
    @cv      = Monitor::ConditionVariable.new(@monitor)

    @allocated = {}
    @available = Array.new(eager ? maximum_size : 0, &block)

    self.timeout      = timeout
    self.collection   = collection
    self.detach_if    = detach_if
    self.maximum_size = maximum_size
  end

  def checkout(scope: nil, &block)
    raise "Can't checkout with a non-frozen scope" unless scope.frozen?

    if object = current_object(scope: scope)
      yield object
    else
      checkout_object(scope: scope, &block)
    end
  end

  def size
    sync { @allocated.inject(@available.size){|sum, (h, k)| sum + k.length} }
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

  def detach_if=(callable)
    raise "Object given for Pond detach_if must respond to #call" unless callable.respond_to?(:call)
    sync { @detach_if = callable }
  end

  private

  def checkout_object(scope:)
    lock_object(scope: scope)
    yield current_object(scope: scope)
  ensure
    unlock_object(scope: scope)
  end

  def lock_object(scope:)
    deadline = Time.now + @timeout

    until current_object(scope: scope)
      raise Timeout if (time_left = deadline - Time.now) < 0

      sync do
        if object = get_object(time_left)
          set_current_object(object, scope: scope)
        end
      end
    end

    # We need to protect changes to @allocated and @available with the monitor
    # so that #size always returns the correct value. But, we don't want to
    # call the instantiation block while we have the lock, since it may take a
    # long time to return. So, we set the checked-out object to the block as a
    # signal that it needs to be called.
    if current_object(scope: scope) == @block
      set_current_object(@block.call, scope: scope)
    end
  end

  def unlock_object(scope:)
    object               = nil
    detach_if            = nil
    should_return_object = nil

    sync do
      object               = current_object(scope: scope)
      detach_if            = self.detach_if
      should_return_object = object && object != @block && size <= maximum_size
    end

    begin
      should_return_object = !detach_if.call(object) if should_return_object
      detach_check_finished = true
    ensure
      sync do
        @available << object if detach_check_finished && should_return_object
        @allocated[scope].delete(Thread.current)
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

  def current_object(scope:)
    sync { (@allocated[scope] ||= {})[Thread.current] }
  end

  def set_current_object(object, scope:)
    sync { (@allocated[scope] ||= {})[Thread.current] = object }
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
