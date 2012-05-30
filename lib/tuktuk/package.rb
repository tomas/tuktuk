require 'mail'

module Package

  class << self

    def new(message)
      mail = message[:html_body] ? mixed(message) : plain(message)
      mail.charset = 'UTF-8'

      mail['In-Reply-To'] = message[:in_reply_to] if message[:in_reply_to]
      mail['List-Archive'] = message[:list_archive] if message[:list_archive] # https://github.com/tomas/prey
      mail['List-Id'] = message[:list_id] if message[:list_id] # <prey.tomas.github.com>

      if message[:return_path]
        mail['Return-Path'] = message[:return_path]
        mail['Bounces-To'] = message[:return_path]
        mail['Errors-To'] = message[:return_path]
      end

      mail
    end

    def plain(message)
      mail = Mail.new do
        from        message[:from]
        to          message[:to]
        reply_to    message[:reply_to] if message[:reply_to]
        # sender    message[:sender] if message[:sender]
        subject     message[:subject]
        message_id  message[:message_id] if message[:message_id]
        body        message[:body]
      end
    end

    def mixed(message)
      mail = Mail.new do
        from        message[:from]
        to          message[:to]
        reply_to    message[:reply_to] if message[:reply_to]
        # sender    message[:sender] if message[:sender]
        subject     message[:subject]
        message_id  message[:message_id] if message[:message_id]
        text_part do
          body      message[:body]
        end
        html_part do
          content_type 'text/html; charset=UTF-8'
          body      message[:html_body]
        end
      end
    end

  end

end
