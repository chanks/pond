# Pond

Pond is a gem that offers thread-safe object pooling. It can wrap anything that is costly to instantiate, but is usually used for connections. Pond is very similar to the `connection_pool` gem, with the major difference being that Pond instantiates objects lazily, which is important for things with high overhead like Postgres connections.

## Installation

Add this line to your application's Gemfile:

    gem 'pond'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pond

## Usage

    require 'pond'
    require 'redis'

    pond = Pond.new(:maximum_size => 5, :timeout => 0.5) { Redis.new }

    # No connections are established until we need one:
    pond.checkout do |redis|
      redis.incr 'my_counter'
      redis.lpush 'my_list', 'item'
    end

    # Alternatively, wrap it:
    $redis = Pond.wrap(:maximum_size => 5, :timeout => 0.5) { Redis.new }

    # You can now use $redis as you normally would.
    $redis.incr 'my_counter'
    $redis.lpush 'my_list', 'item'

    $redis.pipelined do
      # All these commands go to the same Redis connection, and so are pipelined correctly.
      $redis.incr 'my_counter'
      $redis.lpush 'my_list', 'item'
    end

Options:
* :maximum_size - The maximum number of objects/connections you want the pool to contain. The default is 10.
* :timeout - When attempting to check out a connection but none are available, how many seconds to wait before raising an error. The default is 1.
* :collection - How to manage the objects in the pool. The default is :queue, meaning that pond.checkout will yield the object that hasn't been used in the longest period of time. This is to prevent connections from becoming 'stale'. The other option is :stack, so checkout will yield the object that has most recently been returned to the pool. This would be preferable if you're using connections that have their own mechanisms for becoming idle in periods of low activity.
* :eager - Set this to true to fill the pool with instantiated objects when it is created, similar to how `connection_pool` works.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
