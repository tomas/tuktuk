require 'net/smtp'
require 'net/dns/resolver'
require 'dkim'
require 'logger'
require 'tuktuk/package'

DEFAULTS = {
  :retry_sleep =>  10,
  :max_attempts => 3
}

module Tuktuk

  class DNSError < RuntimeError; end
  class MissingFieldsError < ArgumentError; end

  class << self

    def deliver(message, opts = {})
      config.merge(opts)
      mail = Package.new(message)
      mail['X-Mailer'] = opts[:smtp_server_name] || "Tuktuk SMTP #{VERSION}"
      response = lookup_and_deliver(mail)
      return response, mail
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
      email_address.to_s[/@([a-z0-9\._-]+)/i, 1]
    end

    def success(destination)
      logger.info("#{destination} - Successfully sent mail!")
    end

    def error(mail, destination, error, attempt = 1)
      if attempt <= config[:max_attempts] && (error.is_a?(Net::SMTPServerBusy) or error.is_a?(EOFError))
        logger.info "#{destination} - Got #{error.class.name} error. Retrying after #{config[:retry_sleep]} secs..."
        sleep config[:retry_sleep]
        lookup_and_deliver(mail, attempt+1)
      else
        logger.error("#{destination} - Unable to send after #{attempt} attempts: #{error_message} [#{error.class.name}]")
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
      mail.destinations.each do |destination|

        domain = get_domain(destination)
        servers = smtp_servers_for_domain(domain)
        error(mail, destination, DNSError.new("Unknown host: #{domain}")) && next if servers.empty?

        last_error = nil
        servers.each do |server|
          begin
            response = send_now(mail, server, destination)
            break
          rescue => e
            last_error = e
          end
        end
        error(mail, destination, last_error, attempt) if last_error
      end
      response
    end

    def send_now(mail, server, to)
      raw_mail = use_dkim? ? Dkim.sign(mail.to_s).to_s : mail.to_s

      from = mail.return_path || mail.sender || mail.from_addrs.first
      logger.info "#{to} - Delivering email at #{server}..."

      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = OpenSSL::SSL::VERIFY_NONE # OpenSSL::SSL::VERIFY_PEER

      domain = config[:domain] || get_domain(to)

      smtp = Net::SMTP.new(server, nil)
      smtp.enable_starttls_auto(context)
      smtp.start(domain, nil, nil, nil) do |smtp|
        response = smtp.send_message(raw_mail, from, to)
        logger.info response.message
      end

      success(to)
      response
    end

  end

end
