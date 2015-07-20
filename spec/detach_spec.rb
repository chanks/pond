require 'spec_helper'

describe Pond, "#detach_on_checkin" do
  before do
    int  = 0
    @pond = Pond.new(eager: true) { int += 1 }
    @pond.available.should == (1..10).to_a
  end

  it "should default to false" do
    @pond.checkout { |i| @pond.detach_on_checkin.should == false }
  end

  it "should remove the current object when it is checked in" do
    @pond.checkout do |int|
      int.should == 1
      @pond.detach_on_checkin = true
    end

    @pond.available.should == [2, 3, 4, 5, 6, 7, 8, 9, 10]
    @pond.allocated.should == {}

    @pond.checkout do |int|
      int.should == 2
      @pond.detach_on_checkin = true
      @pond.detach_on_checkin = false
    end

    @pond.available.should == [3, 4, 5, 6, 7, 8, 9, 10, 2]
    @pond.allocated.should == {}

    @pond.checkout do |int|
      int.should == 3
      @pond.detach_on_checkin = true
    end

    @pond.available.should == [4, 5, 6, 7, 8, 9, 10, 2]
    @pond.allocated.should == {}
  end

  it "should be local to a specific Pond instance" do
    s = ('a'..'z').to_a
    @pond2 = Pond.new(eager: true) { s.shift }
    @pond2.available.should == ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']
    @pond2.allocated.should == {}

    @pond.checkout do |i|
      expect { @pond2.detach_on_checkin        }.to raise_error
      expect { @pond2.detach_on_checkin = true }.to raise_error

      @pond2.checkout do |s|
        @pond.detach_on_checkin = true
      end

      @pond2.available.should == ['b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'a']
      @pond2.allocated.should == {}
    end

    @pond.available.should  == [2, 3, 4, 5, 6, 7, 8, 9, 10]
    @pond2.available.should == ['b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'a']
    @pond.allocated.should  == {}
    @pond2.allocated.should == {}
  end

  it "should raise an error if there's no current object" do
    expect { @pond.detach_on_checkin        }.to raise_error
    expect { @pond.detach_on_checkin = true }.to raise_error
  end
end
