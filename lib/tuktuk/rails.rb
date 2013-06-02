if ActionMailer::Base.respond_to?(:add_delivery_method)
	
	ActionMailer::Base.add_delivery_method :tuktuk, Tuktuk

	module Tuktuk

		# called from ActionMailer to initialize deliveries
		def self.new(options = {})
			self.options = options
			self
		end

	end

else

	class ActionMailer::Base

		def perform_delivery_tuktuk(mail)
			Tuktuk.deliver!(mail)
	  end

	end
	
end