require 'net/smtp'
require 'dkim'
require 'logger'
require 'work_queue'

%w(package cache dns).each { |lib| require "tuktuk/#{lib}" }
require 'tuktuk/version' unless defined?(Tuktuk::VERSION)

DEFAULTS = {
  :retry_sleep  => 10,
  :max_attempts => 3,
  :max_workers  => 0,
  :read_timeout => 20,
  :open_timeout => 20,
  :verify_ssl   => true,
  :log_to       => nil # $stdout,
}

module Tuktuk

  class DNSError < RuntimeError; end
  class MissingFieldsError < ArgumentError; end

  class << self

    def cache
      @cache ||= Cache.new(100)
    end

    def deliver(message, opts = {})
      self.options = opts if opts.any?
      mail = Package.new(message)
      response = lookup_and_deliver(mail)
      return response, mail
    end

    def deliver_many(messages, opts = {})
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

    def success(to)
      logger.info("#{to} - Successfully sent!")
    end

    def error(mail, to, error, attempt)
      if attempt < config[:max_attempts] and (error.is_a?(EOFError) || error.is_a?(Timeout::Error))
        logger.info "#{to} - Got #{error.class.name} error. Retrying after #{config[:retry_sleep]} secs..."
        sleep config[:retry_sleep]
        lookup_and_deliver(mail, attempt+1)
      else
        logger.error("#{to} - Couldn't send after #{attempt} attempts: #{error.message} [#{error.class.name}]")
        raise error
      end
    end

    def get_domain(email_address)
      email_address && email_address.to_s[/@([a-z0-9\._-]+)/i, 1]
    end

    def reorder_by_domain(array)
      hash = {}
      array.each_with_index do |message, i|
        mail = Package.new(message, i)
        raise "Multiple destinations for email: #{message.inspect}" if mail.destinations.count > 1

        if to = mail.destinations.first and domain = get_domain(to)
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
        raise MissingFieldsError, "No destinations found! You need to pass a :to field."
      end

      response = nil
      mail.destinations.each do |to|

        domain = get_domain(to)
        servers = smtp_servers_for_domain(domain)
        error(mail, to, DNSError.new("No MX records for domain #{domain}"), attempt) && next if servers.empty?

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

    def lookup_and_deliver_many(by_domain)
      if config[:max_workers] && config[:max_workers] > 0
        lookup_and_deliver_many_threaded(by_domain)
      else
        lookup_and_deliver_many_sync(by_domain)
      end
    end

    def lookup_and_deliver_many_threaded(by_domain)
      queue = WorkQueue.new(config[:max_workers])
      responses = []

      by_domain.each do |domain, mails|
        queue.enqueue_b(domain, mails) do |domain, mails|
          # send emails and then assign responses to array according to mail index
          rr = lookup_and_deliver_by_domain(domain, mails)
          rr.each do |resp, mail|
            responses[mail.array_index] = [resp, mail]
          end
        end # worker
      end

      queue.join
      responses
    end

    def lookup_and_deliver_many_sync(by_domain)
      responses = []
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

      unless servers = smtp_servers_for_domain(domain)
        err = DNSError.new("No MX Records for domain #{domain}")
        mails.each {|mail| responses.push [err, mail] }
        return responses
      end

      last_error = nil
      servers.each do |server|
        begin
          send_many_now(server, mails).each do |mail, resp|
            responses.push [resp, mail]
          end
          break
        rescue => e
          # logger.error e.message
          last_error = e
        end
      end

      if last_error # got error at server level, mark all messages with errors
        mails.each {|mail| responses.push [last_error, mail] }
      end

      responses
    end

    def send_now(mail, server, to)
      logger.info "#{to} - Delivering email at #{server}..."
      from = get_from(mail)

      response = nil
      server = 'localhost' if ENV['DEBUG']
      smtp = init_connection(server)
      smtp.start(get_helo_domain(from), nil, nil, nil) do |smtp|
        response = smtp.send_message(get_raw_mail(mail), from, to)
        logger.info "#{to} - [SENT] #{response.message.strip}"
      end

      success(to)
      response
    end

    def send_many_now(server, mails)
      logger.info "Delivering #{mails.count} mails at #{server}..."
      responses = {}
      timeout_error = nil

      server = 'localhost' if ENV['DEBUG']
      smtp = init_connection(server)
      smtp.start(get_helo_domain, nil, nil, nil) do |smtp|
        mails.each do |mail|
          unless timeout_error
            begin
              resp = smtp.send_message(get_raw_mail(mail), get_from(mail), mail.to)
            rescue Net::SMTPError, EOFError, Timeout::Error => e # may be Net::SMTPFatalError (550 Mailbox not found)
              # logger.error e.inspect
              timeout_error = e if e.is_a?(Timeout::Error)
              resp = e
            end
          end
          responses[mail] = timeout_error || resp
          status = resp.is_a?(Net::SMTP::Response) ? 'SENT' : 'ERROR'
          logger.info "#{mail.to} [#{status}] #{responses[mail].message.strip}" # both error and response have this method
        end
      end

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
