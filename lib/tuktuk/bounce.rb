module Tuktuk

class Bounce < RuntimeError

  HARD_BOUNCE_CODES = [
    501, # Bad address syntax (eg. "i.user.@hotmail.com")
    504, # mailbox is disabled
    511, # sorry, no mailbox here by that name (#5.1.1 - chkuser)
    540, # recipient's email account has been suspended.
    550, # Requested action not taken: mailbox unavailable
    552, # Spam Message Rejected -- Requested mail action aborted: exceeded storage allocation
    554, # Recipient address rejected: Policy Rejection- Abuse. Go away -- This user doesn't have a yahoo.com account
    563, # ERR_MSG_REJECT_BLACKLIST, message has blacklisted content and thus I reject it
    571  # Delivery not authorized, message refused
  ]

  def self.type(e)
    if e.is_a?(Net::SMTPFatalError) and code = e.to_s[0..2] and HARD_BOUNCE_CODES.include? code.to_i
      HardBounce.new(e)
    else
      SoftBounce.new(e) # either soft mailbox bounce, timeout or server bounce
    end
  end

  def code
    if str = to_s[0..2] and str.gsub(/[^0-9]/, '') != ''
      str.to_i
    end
  end

end

class HardBounce < Bounce; end
class SoftBounce < Bounce; end

end
