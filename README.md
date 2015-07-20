# Pond

Pond is a gem that offers thread-safe object pooling. It can wrap anything that is costly to instantiate, but is usually used for connections. It is intentionally very similar to the `connection_pool` gem, but is intended to be more efficient and flexible. It instantiates objects lazily by default, which is important for things with high overhead like Postgres connections. It can also be dynamically resized.

Also, it was pretty fun to write.

## Installation

Add this line to your application's Gemfile:

    gem 'pond'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pond

## Usage

```ruby
require 'pond'
require 'redis'

$redis_pond = Pond.new(:maximum_size => 5, :timeout => 0.5) { Redis.new }

# No connections are established until we need one:
$redis_pond.checkout do |redis|
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
```

Options:
* :maximum_size - The maximum number of objects you want the pool to contain. The default is 10.
* :timeout - When attempting to check out an object but none are available, how many seconds to wait before raising a `Pond::Timeout` error. The default is 1.
* :collection - How to manage the objects in the pool. The default is :queue, meaning that pond.checkout will yield the object that hasn't been used in the longest period of time. This is to prevent connections from becoming 'stale'. The alternative is :stack, so checkout will yield the object that has most recently been returned to the pool. This would be preferable if you're using connections that have their own logic for becoming idle in periods of low activity.
* :eager - Set this to true to fill the pool with instantiated objects when it is created, similar to how `connection_pool` works.

#### Detaching Objects

If you don't want a checked out object to remain in the pool anymore, you can set pond.detach_on_checkin = true while the object is still checked out. Then, when the block ends, the object will not be returned to the pool - instead, Pond will detach it and make it available for garbage collection.

This is helpful if, for example, a connection becomes unusable:

```ruby
$pool = Pond.new { PG::Connection.new }

$pool.checkout do |connection|
  begin
    connection.execute "SELECT * FROM table"
  rescue PG::ConnectionError => e
    # PG connections raising this socket error are broken and can't be
    # repaired, so let it detach.
    if e.message =~ /can't get socket descriptor/
      $pool.detach_on_checkin = true
    end

    # Bubble up exception so it can be handled by whatever error handling
    # procedure is in place.
    raise
  end
end
```

This ensures that other threads won't pick up the bad process. The Pond will spawn a new connection to replace that one, if necessary, up to the maximum number of objects.

## Contributing

I don't plan on adding too many more features to Pond, since I want to keep its design simple. If there's something you'd like to see it do, open an issue so we can discuss it before going to the trouble of creating a pull request.
