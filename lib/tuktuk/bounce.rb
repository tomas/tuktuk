class Bounce < RuntimeError

  HARD_BOUNCE_CODES = [
    511, # sorry, no mailbox here by that name (#5.1.1 - chkuser)
    550, # Requested action not taken: mailbox unavailable
    554, # Recipient address rejected: Policy Rejection- Abuse. Go away.
    571  # Delivery not authorized, message refused
  ]

  def self.type(e)
    if e.is_a? DNSError
      HardServerBounce.new(e)
    elsif e.is_a? Net::SMTPFatalError
      if code = e.to_s[0..2] and HARD_BOUNCE_CODES.include? code.to_i
        HardMailboxBounce.new(e)
      else
        SoftMailboxBounce.new(e)
      end
    else
      SoftServerBounce.new(e)
    end
  end

end

class HardBounce < Bounce; end
class SoftBounce < Bounce; end
class HardMailboxBounce < HardBounce; end
class SoftMailboxBounce < SoftBounce; end
class HardServerBounce < HardBounce; end
class SoftServerBounce < SoftBounce; end
class DNSError < HardServerBounce; end
