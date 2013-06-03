if ActionMailer::Base.respond_to?(:add_delivery_method)
  
  ActionMailer::Base.add_delivery_method :tuktuk, Tuktuk

  module Tuktuk

    def self.new(options)
      self.options = options
      self
    end

  end

else
  
  require 'tuktuk'

  class ActionMailer::Base

    def self.tuktuk_settings=(opts)
      Tuktuk.options = opts
    end

    def perform_delivery_tuktuk(mail)
      Tuktuk.deliver!(mail)
    end

  end
  
end