require 'spec_helper'

describe Pond do
  it "should yield objects specified in the block" do
    pond = Pond.new { 1 }
    pond.checkout { |i| i.should == 1 }
  end

  it "should return the value returned by the block" do
    pond = Pond.new { 1 }
    value = pond.checkout { |i| 'value' }
    value.should == 'value'
  end

  it "should instantiate objects only as needed" do
    int  = 0
    pond = Pond.new { int += 1 }

    pond.size.should == 0

    pond.checkout do |i|
      pond.available.should == []
      pond.allocated.should == {Thread.current => 1}
      i.should == 1
    end

    pond.available.should == [1]
    pond.allocated.should == {}
    pond.size.should == 1

    pond.checkout do |i|
      pond.available.should == []
      pond.allocated.should == {Thread.current => 1}
      i.should == 1
    end

    pond.available.should == [1]
    pond.allocated.should == {}
    pond.size.should == 1
  end

  it "should eagerly instantiate objects if the option is given" do
    int = 0
    pond = Pond.new(:eager => true){int += 1}
    pond.available.should == (1..10).to_a
  end

  it "should not instantiate objects in excess of the specified maximum_size" do
    object = nil
    pond = Pond.new(:maximum_size => 1) { object = Object.new }
    object_ids = []

    threads = 20.times.map do
      pond.checkout do |obj|
        object_ids << obj.object_id
      end
    end

    object_ids.uniq.should == [object.object_id]
  end

  it "should check out different objects to different threads" do
    int  = 0
    pond = Pond.new { int += 1 }

    q1, q2 = Queue.new, Queue.new

    t = Thread.new do
      pond.checkout do |i|
        i.should == 1
        q1.push nil
        q2.pop
      end
    end

    q1.pop

    pond.size.should == 1
    pond.allocated.should == {t => 1}
    pond.available.should == []

    pond.checkout { |i| i.should == 2 }

    pond.size.should == 2
    pond.allocated.should == {t => 1}
    pond.available.should == [2]

    q2.push nil
    t.join

    pond.allocated.should == {}
    pond.available.should == [2, 1]
  end

  it "should be re-entrant" do
    pond = Pond.new { Object.new }
    pond.checkout do |obj1|
      pond.checkout do |obj2|
        obj1.should == obj2
      end
    end
  end

  it "should support a thread checking out objects from distinct Pond instances" do
    pond1 = Pond.new { [] }
    pond2 = Pond.new { {} }

    pond1.checkout do |one|
      pond2.checkout do |two|
        one.should == []
        two.should == {}
      end
    end
  end

  it "should yield an object to only one thread when many are waiting" do
    pond = Pond.new(:maximum_size => 1) { 2 }

    q1, q2, q3 = Queue.new, Queue.new, Queue.new

    threads = 4.times.map do
      Thread.new do
        Thread.current[:value] = 0

        q1.push nil

        pond.checkout do |o|
          Thread.current[:value] = o
          q2.push nil
          q3.pop
        end
      end
    end

    4.times { q1.pop }
    q2.pop

    threads.map{|t| t[:value]}.sort.should == [0, 0, 0, 2]

    4.times { q3.push nil }

    threads.each &:join
  end

  it "should treat the collection of objects as a queue" do
    int  = 0
    pond = Pond.new { int += 1 }
    results = []

    q  = Queue.new
    m  = Mutex.new
    cv = ConditionVariable.new

    4.times do
      threads = 4.times.map do
        Thread.new do
          m.synchronize do
            pond.checkout do |i|
              results << i
              q.push nil
              cv.wait(m)
            end
            cv.signal
          end
        end
      end

      4.times { q.pop }
      cv.signal
      threads.each(&:join)
    end

    pond.size.should == 4
    results.should == (1..4).cycle(4).to_a
  end

  it "should treat the collection of objects as a stack, if configured that way" do
    int  = 0
    pond = Pond.new(:collection => :stack) { int += 1 }
    results = []

    q  = Queue.new
    m  = Mutex.new
    cv = ConditionVariable.new

    4.times do
      threads = 4.times.map do
        Thread.new do
          m.synchronize do
            pond.checkout do |i|
              results << i
              q.push nil
              cv.wait(m)
            end
            cv.signal
          end
        end
      end

      4.times { q.pop }
      cv.signal
      threads.each(&:join)
    end

    pond.size.should == 4
    results.should == [1, 2, 3, 4, 4, 3, 2, 1, 1, 2, 3, 4, 4, 3, 2, 1]
  end

  it "should raise a timeout error if it takes too long to return an object" do
    pond = Pond.new(:timeout => 0.01, :maximum_size => 1){1}

    q1, q2 = Queue.new, Queue.new
    t = Thread.new do
      pond.checkout do
        q1.push nil
        q2.pop
      end
    end

    q1.pop

    proc{pond.checkout{}}.should raise_error Pond::Timeout

    q2.push nil
    t.join
  end

  it "with a block that raises an error should check the object back in and propagate the error" do
    pond = Pond.new { 1 }
    proc do
      pond.checkout do
        raise "Blah!"
      end
    end.should raise_error RuntimeError, "Blah!"

    pond.allocated.should == {}
    pond.available.should == [1]
  end

  it "should not be blocking if the object instantiation takes a long time" do
    t = nil
    q1, q2, q3 = Queue.new, Queue.new, Queue.new
    pond = Pond.new do
      q1.push nil
      q2.pop
    end

    q2.push 1

    pond.checkout do |i|
      q1.pop
      i.should == 1

      t = Thread.new do
        pond.checkout do |i|
          i.should == 2
        end
      end

      q1.pop
    end

    pond.checkout { |i| i.should == 1 }

    q2.push 2
    t.join
  end

  it "should not be left in a bad state if object instantiation fails" do
    int = 0
    error = false
    pond = Pond.new do
      raise "Instantiation Error!" if error
      int += 1
    end

    pond.checkout { |i| i.should == 1 }

    pond.size.should == 1
    pond.allocated.should == {}
    pond.available.should == [1]

    error = true

    pond.checkout do |i|
      i.should == 1

      t = Thread.new do
        pond.checkout{}
      end

      proc { t.join }.should raise_error RuntimeError, "Instantiation Error!"
    end

    pond.size.should == 1
    pond.allocated.should == {}
    pond.available.should == [1]
  end

  it "should have its collection type gettable and settable" do
    pond = Pond.new { Object.new }
    pond.collection.should == :queue
    pond.collection = :stack
    pond.collection.should == :stack

    pond = Pond.new(:collection => :stack) { Object.new }
    pond.collection.should == :stack
    pond.collection = :queue
    pond.collection.should == :queue

    procs = [
      proc{pond.collection = nil},
      proc{pond.collection = :blah},
      proc{Pond.new(:collection => :blah) { Object.new }}
    ]

    procs.each { |p| p.should raise_error RuntimeError, /Bad value for Pond collection:/ }
  end

  it "should have its maximum_size gettable and settable" do
    pond = Pond.new { Object.new }
    pond.maximum_size.should == 10
    pond.maximum_size = 7
    pond.maximum_size.should == 7
    pond.maximum_size = 0
    pond.maximum_size.should == 0
    pond.maximum_size = 2
    pond.maximum_size.should == 2

    procs = [
      proc{pond.maximum_size = nil},
      proc{pond.maximum_size = :blah},
      proc{Pond.new(:maximum_size => :blah) { Object.new }},
      proc{pond.maximum_size = 4.0},
      proc{Pond.new(:maximum_size => 4.0) { Object.new }},
    ]

    procs.each { |p| p.should raise_error RuntimeError, /Bad value for Pond maximum_size:/ }
  end
end
