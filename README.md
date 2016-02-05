# Pond

Pond is a gem that offers thread-safe object pooling. It can wrap anything
that is costly to instantiate, but is usually used for connections. It is
intentionally very similar to the `connection_pool` gem, but is intended to be
more efficient and flexible. It instantiates objects lazily by default, which
is important for things with high overhead like Postgres connections. It can
also be dynamically resized, and does not block on object instantiation.

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

* :maximum_size - The maximum number of objects you want the pool to contain.
  The default is 10.
* :timeout - When attempting to check out an object but none are available,
  how many seconds to wait before raising a `Pond::Timeout` error. The
  default is 1. Integers or floats are both accepted.
* :collection - How to manage the objects in the pool. The default is :queue,
  meaning that pond.checkout will yield the object that hasn't been used in
  the longest period of time. This is to prevent connections from becoming
  'stale'. The alternative is :stack, so checkout will yield the object that
  has most recently been returned to the pool. This would be preferable if
  you're using connections that have their own logic for becoming idle in
  periods of low activity.
* :eager - Set this to true to fill the pool with instantiated objects (up to
  the maximum size) when it is created, similar to how the `connection_pool`
  gem works.
* :detach_if - Set this to a callable object that can determine whether
  objects should be returned to the pool or not. See the following example for
  more information.

### Detaching Objects

Sometimes objects in the pool outlive their usefulness (connections may fail)
and it becomes necessary to remove them. Pond's detach_if option is useful for
this - you can pass it any callable object, and Pond will pass it objects from
the pool that have been checked out before they are checked back in. For
example, when using Pond with PostgreSQL connections:

```ruby
require 'pond'
require 'pg'

$pg_pond = Pond.new(:detach_if => lambda {|c| c.finished?}) do
  PG.connect(:dbname => "pond_test")
end
```

Now, after a PostgreSQL connection has been used, but before it is returned to
the pool, it will be passed to that lambda to see if it should be detached or
not. If the lambda returns truthy, the connection will be detached (and made
available for garbage collection), and a new one will be instantiated to
replace it as necessary (until the pool returns to its maximum size).

Be aware that Pond's lock is held while detach_if is called, so make sure
whatever it does is not too slow, since other threads won't be able to check
in or out objects while it runs. This may be addressed in a future release of
Pond.

## Contributing

I don't plan on adding too many more features to Pond, since I want to keep
its design simple. If there's something you'd like to see it do, open an issue
so we can discuss it before going to the trouble of creating a pull request.
