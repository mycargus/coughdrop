module General
  extend ActiveSupport::Concern
  
  def mail_message(user, subject, channel_type=nil)
    channel_type ||= caller_locations(1,1)[0].label
    user.channels_for(channel_type).each do |path|
      mail(to: path, subject: "CoughDrop - #{subject}")
    end
  end  

  module ClassMethods
    def schedule_delivery(delivery_type, *args)
      Worker.schedule_for(:priority, self, :deliver_message, delivery_type, *args)
    end
  
    def deliver_message(method_name, *args)
      begin
        method = self.send(method_name, *args)
        method.respond_to?(:deliver_now) ? method.deliver_now : method.deliver
      rescue AWS::SES::ResponseError => e
      end
    end
  end
end