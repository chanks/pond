require 'spec_helper'

describe Pond, "configuration" do
  it "should eagerly instantiate objects if the option is given" do
    int = 0
    pond = Pond.new(:eager => true){int += 1}
    pond.available.should == (1..10).to_a
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
      proc{Pond.new(:collection => nil) { Object.new }},
      proc{pond.collection = :blah},
      proc{Pond.new(:collection => :blah) { Object.new }}
    ]

    procs.each { |p| p.should raise_error RuntimeError, /Bad value for Pond collection:/ }
  end

  it "should have its timeout gettable and settable" do
    pond = Pond.new { Object.new }
    pond.timeout.should == 1
    pond.timeout = 4
    pond.timeout.should == 4

    pond = Pond.new(:timeout => 3.7) { Object.new }
    pond.timeout.should == 3.7
    pond.timeout = 1.9
    pond.timeout.should == 1.9

    procs = [
      proc{pond.timeout = nil},
      proc{Pond.new(:timeout => nil) { Object.new }},
      proc{pond.timeout = :blah},
      proc{Pond.new(:timeout => :blah) { Object.new }}
    ]

    procs.each { |p| p.should raise_error RuntimeError, /Bad value for Pond timeout:/ }
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
      proc{Pond.new(:maximum_size => nil) { Object.new }},
      proc{pond.maximum_size = :blah},
      proc{Pond.new(:maximum_size => :blah) { Object.new }},
      proc{pond.maximum_size = 4.0},
      proc{Pond.new(:maximum_size => 4.0) { Object.new }},
    ]

    procs.each { |p| p.should raise_error RuntimeError, /Bad value for Pond maximum_size:/ }
  end

  it "when the maximum_size is decreased should free available objects" do
    int  = 0
    pond = Pond.new(:eager => true) { int += 1 }

    pond.available.should == (1..10).to_a
    pond.maximum_size = 8
    pond.available.should == (3..10).to_a
    pond.maximum_size = 10
    pond.available.should == (3..10).to_a
    pond.maximum_size = 9
    pond.available.should == (3..10).to_a
  end

  it "when the maximum_size is decreased should free available objects and checked-out objects upon return" do
    int = 0
    pond = Pond.new(:eager => true, :maximum_size => 2) { int += 1 }
    pond.available.should == [1, 2]

    q1, q2 = Queue.new, Queue.new
    t = Thread.new do
      pond.checkout do |i|
        i.should == 1
        q1.push nil
        q2.pop
      end
    end

    q1.pop

    pond.maximum_size = 0
    pond.maximum_size.should == 0

    pond.size.should == 1
    pond.available.should == []
    pond.allocated.should == {nil => {t => 1}}

    q2.push nil
    t.join

    pond.size.should == 0
    pond.available.should == []
    pond.allocated.should == {nil => {}}
  end
end
