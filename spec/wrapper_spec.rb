require 'spec_helper'

describe Pond::Wrapper do
  class Wrapped
    def pipelined(&block)
      yield
    end
  end

  before do
    @wrapper = Pond.wrap { Wrapped.new }
    @pond    = @wrapper.pond
  end

  it "should proxy method calls to checked out objects" do
    @pond.size.should == 0

    @wrapper.class.should == Wrapped
    @wrapper.respond_to?(:pipelined).should == true
    object_id = @wrapper.object_id

    @pond.size.should == 1
    @pond.allocated.should == {}
    @pond.available.map(&:object_id).should == [object_id]
  end

  it "should return the same object within a block passed to one of its methods" do
    q1, q2 = Queue.new, Queue.new
    oid1, oid2 = nil, nil

    @wrapper.pipelined do
      oid1 = @wrapper.object_id

      t = Thread.new do
        @wrapper.pipelined do
          q1.push nil
          q2.pop

          oid2 = @wrapper.object_id
          oid2.should == @wrapper.object_id
          @wrapper
        end
      end

      q1.pop

      @wrapper.object_id.should == oid1

      @pond.allocated.keys.should == [Thread.current, t]
      @pond.available.should == []

      q2.push nil
      t.join

      @wrapper.object_id.should == oid1
      @wrapper.object_id.should == oid1
    end
  
    @pond.allocated.should == {}
    @pond.available.map(&:object_id).should == [oid2, oid1]
  end
end
