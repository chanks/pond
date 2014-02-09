require 'spec_helper'

describe Pond, "#checkout" do
  it "should yield objects specified in the block" do
    pond = Pond.new { 1 }
    pond.checkout { |i| i.should == 1 }
  end

  it "should return the value returned by the block" do
    pond = Pond.new { 1 }
    value = pond.checkout { |i| 'value' }
    value.should == 'value'
  end

  it "should instantiate objects as needed" do
    int  = 0
    pond = Pond.new { int += 1 }

    pond.size.should == 0
    pond.checkout { |i| i.should == 1 }
    pond.size.should == 1
    pond.checkout { |i| i.should == 1 }
    pond.size.should == 1
  end

  it "should not instantiate objects in excess of the specified maximum_size" do
    object = Object.new
    pond   = Pond.new(:maximum_size => 1){object}
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
        q1.push nil
        i.should == 1
        q2.pop
      end
    end

    q1.pop
    pond.size.should == 1
    pond.checkout { |i| i.should == 2 }
    pond.size.should == 2
    q2.push nil

    t.join
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

  it "should treat the collection of objects as a queue, not a stack" do
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
end
