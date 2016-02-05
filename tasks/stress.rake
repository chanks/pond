require 'pond'

desc "Stress test the Pond gem to check for concurrency issues."
task :stress do
  detach_if = proc do |obj|
    raise "Bad Detach!" if rand < 0.05
    obj != "Good!"
  end

  pond = Pond.new(detach_if: detach_if) do
    raise "Bad Instantiation!" if rand < 0.05
    "Good!"
  end

  threads =
    20.times.map do
      Thread.new do
        10_000.times do
          begin
            pond.checkout do |o|
              raise "Uh-oh!" unless o == "Good!"
              o.replace "Bad!" if rand < 0.05
            end
          rescue => e
            raise e unless ["Bad Detach!", "Bad Instantiation!"].include?(e.message)
          end
        end
      end
    end

  threads.each(&:join)

  puts "Stress test succeeded!"
end
