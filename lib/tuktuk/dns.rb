begin
  require 'resolv'
rescue
  require 'net/dns/resolve'
end

module Tuktuk

module DNS

  class << self

    def get_mx(host)
      if defined?(Resolv::DNS)
        get_using_resolve(host)
      else
        get_using_net_dns(host)
      end
    end

    def get_using_resolve(host)
      Resolv::DNS.open do |dns|
        if res = dns.getresources(host, Resolv::DNS::Resource::IN::MX)
          sort_mx(res)
        end
      end
    end

    def get_using_net_dns(host)
      if res = Net::DNS::Resolver.new.mx(host)
        sort_mx(res)
      end
    end

    def sort_mx(res)
      res.sort {|x,y| x.preference <=> y.preference}.map { |rr| rr.exchange.to_s }
    end

  end

end

end
