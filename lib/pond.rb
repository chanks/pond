require 'thread'

require 'pond/version'

class Pond
  attr_reader :allocated

  def initialize(options = {}, &block)
    @max   = options[:maximum_size] || 10
    @block = block
    @mutex = Mutex.new
    @cv    = ConditionVariable.new

    @available = []
    @allocated = {}
  end

  def checkout(&block)
    if object = @mutex.synchronize { @allocated[Thread.current] }
      yield object
    else
      _checkout(&block)
    end
  end

  def size
    @mutex.synchronize { _size }
  end

  private

  def _checkout
    object = nil

    loop do
      @mutex.synchronize do
        if @available.empty?
          if _size >= @max
            @cv.wait(@mutex)
          else
            object = @block.call
          end
        else
          object = @available.shift
        end

        @allocated[Thread.current] = object if object
      end

      break if object
    end

    yield object
  ensure
    if object
      @mutex.synchronize do
        @allocated.delete(Thread.current)
        @available << object
        @cv.signal
      end
    end
  end

  def _size
    @available.size + @allocated.size
  end
end
