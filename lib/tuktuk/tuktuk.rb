require 'net/smtp'
require 'dkim'
require 'logger'
require 'work_queue'

%w(package cache dns bounce).each { |lib| require "tuktuk/#{lib}" }
require 'tuktuk/version' unless defined?(Tuktuk::VERSION)

DEFAULTS = {
  :helo_domain  => nil,
  :max_workers  => 0,
  :read_timeout => 20,
  :open_timeout => 20,
  :verify_ssl   => true,
  :log_to       => nil # $stdout,
}

module Tuktuk

  class << self

    def cache
      @cache ||= Cache.new(100)
    end

    def deliver(message, opts = {})
      raise 'Please pass a valid message object.' unless messages[:to]
      self.options = opts if opts.any?
      mail = Package.new(message)
      response = lookup_and_deliver(mail)
      return response, mail
    end

    def deliver_many(messages, opts = {})
      raise 'Please pass an array of messages.' unless messages.any?
      self.options = opts if opts.any?
      messages_by_domain = reorder_by_domain(messages)
      lookup_and_deliver_many(messages_by_domain)
    end

    def options=(hash)
      if dkim_opts = hash.delete(:dkim)
        self.dkim = dkim_opts
      end
      config.merge!(hash)
    end

    def dkim=(dkim_opts)
      Dkim::domain      = dkim_opts[:domain]
      Dkim::selector    = dkim_opts[:selector]
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
      @logger ||= Logger.new(config[:log_to])
    end

    def get_domain(email_address)
      email_address && email_address.to_s[/@([a-z0-9\._-]+)/i, 1]
    end

    def reorder_by_domain(array)
      hash = {}
      array.each_with_index do |message, i|
        mail = Package.new(message, i)
        raise "Invalid destination count: #{mail.destinations.count}" if mail.destinations.count != 1

        if to = mail.destinations.first and domain = get_domain(to)
          domain = domain.downcase
          hash[domain] = [] if hash[domain].nil?
          hash[domain].push(mail)
        end
      end
      hash
    end

    def smtp_servers_for_domain(domain)
      unless servers = cache.get(domain)
        if servers = DNS.get_mx(domain) and servers.any?
          cache.set(domain, servers)
        end
      end
      servers.any? && servers
    end

    def lookup_and_deliver(mail, attempt = 1)
      if mail.destinations.empty?
        raise "No destinations found! You need to pass a :to field."
      end

      response = nil
      mail.destinations.each do |to|

        domain = get_domain(to)
        unless servers = smtp_servers_for_domain(domain)
          return HardBounce.new("588 No MX records for domain #{domain}")
        end

        last_error = nil
        servers.each do |server|
          begin
            response = send_now(mail, server, to)
            break
          rescue => e
            last_error = e
          end
        end
        return Bounce.type(last_error) if last_error
      end
      response
    end

    def lookup_and_deliver_many(by_domain)
      if config[:max_workers] && config[:max_workers] != 0
        lookup_and_deliver_many_threaded(by_domain)
      else
        lookup_and_deliver_many_sync(by_domain)
      end
    end

    def lookup_and_deliver_many_threaded(by_domain)
      count = config[:max_workers].is_a?(Integer) ? config[:max_workers] : nil
      queue = WorkQueue.new(count)
      responses = []

      logger.info("Delivering emails to #{by_domain.keys.count} domains...")
      by_domain.each do |domain, mails|
        queue.enqueue_b(domain, mails) do |domain, mails|
          # send emails and then assign responses to array according to mail index
          rr = lookup_and_deliver_by_domain(domain, mails)
          rr.each do |resp, mail|
            responses[mail.array_index] = [resp, mail]
          end
        end # worker
      end

      queue.join # wait for threads to finish
      queue.kill # terminate queue
      responses
    end

    def lookup_and_deliver_many_sync(by_domain)
      responses = []

      logger.info("Delivering emails to #{by_domain.keys.count} domains...")
      by_domain.each do |domain, mails|
        # send emails and then assign responses to array according to mail index
        rr = lookup_and_deliver_by_domain(domain, mails)
        rr.each do |resp, mail|
          responses[mail.array_index] = [resp, mail]
        end
      end
      responses
    end

    def lookup_and_deliver_by_domain(domain, mails)
      responses = []
      total = mails.count

      unless servers = smtp_servers_for_domain(domain)
        err = HardBounce.new("588 No MX Records for domain #{domain}")
        mails.each { |mail| responses.push [err, mail] }
        return responses
      end

      servers.each do |server|
        send_many_now(server, mails).each do |mail, resp|
          responses.push [resp, mail]
          mails.delete(mail) # remove it from list, to avoid duplicate delivery
        end
        logger.info "#{responses.count}/#{total} mails processed on #{domain}'s MX: #{server}."
        break if responses.count == total
      end

      # if we still have emails in queue, mark them with the last error which prevented delivery
      if mails.any? and @last_error
        bounce = Bounce.type(@last_error)
        logger.info "#{mails.count} mails still pending. Marking as #{bounce.class}..."
        mails.each { |m| responses.push [bounce, m] }
      end

      responses
    end

    def send_now(mail, server, to)
      logger.info "#{to} - Delivering email at #{server}..."
      from = get_from(mail)

      response = nil
      server = 'localhost' if ENV['DEBUG']
      socket = init_connection(server)
      socket.start(get_helo_domain(from), nil, nil, nil) do |smtp|
        response = smtp.send_message(get_raw_mail(mail), from, to)
        logger.info "#{to} - [SENT] #{response.message.strip}"
      end

      response
    end

    def send_many_now(server, mails)
      logger.info "Delivering #{mails.count} mails at #{server}..."
      responses = {}

      server = 'localhost' if ENV['DEBUG']
      socket = init_connection(server)
      socket.start(get_helo_domain, nil, nil, nil) do |smtp|
        mails.each do |mail|
          begin
            resp = smtp.send_message(get_raw_mail(mail), get_from(mail), mail.to)
            smtp.send(:getok, 'RSET') if server['hotmail'] # fix for '503 Sender already specified'
          rescue Net::SMTPFatalError => e # error code 5xx, except for 500, like: 550 Mailbox not found
            resp = Bounce.type(e)
          end
          responses[mail] = resp
          logger.info "#{mail.to} [#{responses[mail].class}] #{responses[mail].message.strip}" # both error and response have this method
        end
      end

      responses
    rescue => e # SMTPServerBusy, SMTPSyntaxError, SMTPUnsupportedCommand, SMTPUnknownError (unexpected reply code)
	    logger.error "[SERVER ERROR: #{server}] #{e.message}"
	    @last_error = e
      responses
    end

    def get_raw_mail(mail)
      use_dkim? ? Dkim.sign(mail.to_s).to_s : mail.to_s
    end

    def get_from(mail)
      mail.return_path || mail.sender || mail.from_addrs.first
    end

    def get_helo_domain(from = nil)
      Dkim::domain || config[:helo_domain] || (from && get_domain(from))
    end

    def init_connection(server)
      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = config[:verify_ssl] ?
        OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

      smtp = Net::SMTP.new(server, nil)
      smtp.enable_starttls_auto(context)
      smtp.read_timeout = config[:read_timeout] if config[:read_timeout]
      smtp.open_timeout = config[:open_timeout] if config[:open_timeout]
      smtp
    end

  end

end
