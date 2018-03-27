require 'spec_helper'

describe Pond::Wrapper do
  class Wrapped
    # JRuby implements BasicObject#object_id, so we need a minor workaround.
    def id
      object_id
    end

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
    id = @wrapper.id

    @pond.size.should == 1
    @pond.allocated.should == {nil => {}}
    @pond.available.map(&:id).should == [id]
  end

  it "should return the same object within a block passed to one of its methods" do
    q1, q2 = Queue.new, Queue.new
    id1, id2 = nil, nil

    @wrapper.pipelined do
      id1 = @wrapper.id

      t = Thread.new do
        @wrapper.pipelined do
          q1.push nil
          q2.pop

          id2 = @wrapper.id
          id2.should == @wrapper.id
          @wrapper
        end
      end

      q1.pop

      @wrapper.id.should == id1

      @pond.allocated[nil].keys.should == [Thread.current, t]
      @pond.available.should == []

      q2.push nil
      t.join

      @wrapper.id.should == id1
      @wrapper.id.should == id1
    end
  
    @pond.allocated.should == {nil => {}}
    @pond.available.map(&:id).should == [id2, id1]
  end
end
