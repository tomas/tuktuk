if ActionMailer::Base.respond_to?(:add_delivery_method)
	
	ActionMailer::Base.add_delivery_method :tuktuk, Tuktuk

	module Tuktuk

		def self.deliver!(mail)
			@logger = Rails.logger unless config[:log_to]
			resp, email = deliver(mail)
			raise resp if resp.is_a?(Exception)
		end

		def self.new(options = {})
			options = options
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