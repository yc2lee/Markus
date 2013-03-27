class ResqueClass
  include Resque::Plugins::Status

  def self.queue
    :resque_class
  end

  # calling sequence
  # j = ResqueClass.create(:length => 32)
  def perform
    puts "#{options.inspect}"
    time = options["length"] || 90

    1.upto(time).each do |x|
      sleep 1
      at(x, time, "Howdy! My UUID is #{@uuid}")
    end
    completed("Finished!")
  end
end


