class ResqueClass
  include Resque::Plugins::Status

  @@mycounter = 0
  cattr_accessor :mycounter

  def self.queue
    :resque_class
  end

  def perform
    puts "#{options.inspect}"
    time = options["length"]
    if time.nil?
      time = 90
    end
    @@mycounter += 1
    1.upto(90).each do |x|
      sleep 1
      at(x, 90, "Howdy! The count is at #{@@mycounter}.")
    end
    completed("Finished!")
  end
end


