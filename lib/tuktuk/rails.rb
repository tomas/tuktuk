if ActionMailer::Base.respond_to?(:add_delivery_method)
	
	ActionMailer::Base.add_delivery_method :tuktuk, Tuktuk

else

	class ActionMailer::Base

		def perform_delivery_tuktuk(mail)
			resp, email = Tuktuk.deliver(mail)
			raise resp if resp.is_a?(Exception)
	  end

	end
	
end