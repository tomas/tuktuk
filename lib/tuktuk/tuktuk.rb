require 'net/smtp'
require 'net/dns/resolver'
require 'dkim'
require 'logger'
require 'tuktuk/package'

DEFAULTS = {
  :retry_sleep =>  10,
  :max_attempts => 3,
  :mailer => "Tuktuk SMTP #{VERSION}",
  :log_level => Logger::INFO
}

module Tuktuk

  class DNSError < RuntimeError; end
  class MissingFieldsError < ArgumentError; end

  class << self

    def deliver(message, opts = {})
      options = opts
      mail = Package.new(message)
      mail['X-Mailer'] = config[:mailer]
      response = lookup_and_deliver(mail)
      return response, mail
    end

    def options=(hash)
      if dkim_opts = hash.delete(:dkim)
        self.dkim = dkim_opts
      end
      config.merge!(hash)
    end

    def dkim=(dkim_opts)
      Dkim::domain = dkim_opts[:domain]
      Dkim::selector = dkim_opts[:selector]
      Dkim::private_key = dkim_opts[:private_key]
    end

    private

    def config
      @config ||= DEFAULTS
    end

    def use_dkim?
      !Dkim::domain.nil?
    end

    def logger
      @logger ||= Logger.new(config[:logfile])
    end

    def get_domain(email_address)
      email_address && email_address.to_s[/@([a-z0-9\._-]+)/i, 1]
    end

    def success(destination)
      logger.info("#{destination} - Successfully sent!")
    end

    def error(mail, to, error, attempt = 1)
      if attempt <= config[:max_attempts] && (error.is_a?(Net::SMTPServerBusy) or error.is_a?(EOFError))
        logger.info "#{to} - Got #{error.class.name} error. Retrying after #{config[:retry_sleep]} secs..."
        sleep config[:retry_sleep]
        lookup_and_deliver(mail, attempt+1)
      else
        logger.error("#{to} - Unable to send after #{attempt} attempts: #{error.message} [#{error.class.name}]")
        raise error
      end
    end

    def smtp_servers_for_domain(domain)
      res = Net::DNS::Resolver.new
      if mx = res.mx(domain)
        mx.sort {|x,y| x.preference <=> y.preference}.map {|rr| rr.exchange}
      else
        raise DNSError, "Could not locate MX records for domain #{domain}."
      end
    end

    def lookup_and_deliver(mail, attempt = 1)
      raise MissingFieldsError, "No destinations found! You need to pass a :to field." if mail.destinations.empty?

      response = nil
      mail.destinations.each do |to|

        domain = get_domain(to)
        servers = smtp_servers_for_domain(domain)
        error(mail, to, DNSError.new("Unknown host: #{domain}")) && next if servers.empty?

        last_error = nil
        servers.each do |server|
          begin
            response = send_now(mail, server, to)
            break
          rescue => e
            last_error = e
          end
        end
        error(mail, to, last_error, attempt) if last_error
      end
      response
    end

    def send_now(mail, server, to)
      logger.info "#{to} - Delivering email at #{server}..."

      raw_mail = use_dkim? ? Dkim.sign(mail.to_s).to_s : mail.to_s
      from = mail.return_path || mail.sender || mail.from_addrs.first
      helo_domain = Dkim::domain || config[:helo_domain] || get_domain(from)

      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = OpenSSL::SSL::VERIFY_NONE # OpenSSL::SSL::VERIFY_PEER

      smtp = Net::SMTP.new(server, nil)
      smtp.enable_starttls_auto(context)

      response = nil
      smtp.start(helo_domain, nil, nil, nil) do |smtp|
        response = smtp.send_message(raw_mail, from, to)
        logger.info "#{to} - #{response.message.strip}"
      end

      success(to)
      response
    end

  end

end
