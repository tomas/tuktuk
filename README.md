Tuktuk - SMTP client for Ruby
=============================

Unlike Pony (which is friggin' awesome by the way) Tuktuk does not rely on 
`sendmail` or a separate SMTP server in order to send email. Tuktuk looks up the
MX servers of the destination address and connects directly using Net::SMTP. 
This way you don't need to install Exim or Postfix and you can actually handle 
response status codes -- like bounces, 5xx -- within your application. 

Plus, it supports DKIM out of the box.

Delivering mail
---------------

``` ruby
require 'tuktuk'

message = {
  :from => 'you@username.com',
  :to => 'user@yoursite.com',
  :body => 'Hello there',
  :subject => 'Hiya'
}

response, email = Tuktuk.deliver(message)
```

The `response` is either a Net::SMTP::Response object, or a Bounce exception (HardBounce or SoftBounce, depending on the cause). `email` is a [mail](https://github.com/mikel/mail) object. So, to handle bounces you'd do:

``` ruby
[...]

response, email = Tuktuk.deliver(message)

if response.is_a?(Bounce)
  puts 'Email bounced. Type: ' + response.class.name # => HardBounce or SoftBounce
else
  puts 'Email delivered!'
end
```

Delivering multiple
-------------------

With Tuktuk, you can also deliver multiple messages at once. Depending on the `max_workers` config parameter, Tuktuk will either connect sequentially to the target domain's MX servers, or do it in parallel by spawning threads. 

Tuktuk will try to send all emails targeted for a specific domain on the same SMTP session. If a MX server is not responding -- or times out in the middle --, Tuktuk will try to deliver the remaining messages to next MX server, and so on.

To #deliver_many, you need to pass an array of messages, and you'll receive an array of [response, email] elements, just as above.

``` ruby
messages = [ { ... }, { ... }, { ... }, { ... } ] # array of messages

result = Tuktuk.deliver_many(messages)

result.each do |response, email|

  if response.is_a?(Bounce)
    puts 'Email bounced. Type: ' + response.class.name
  else
    puts 'Email delivered!'
  end

end
```

Options & DKIM
--------------

Now, if you want to enable DKIM (and you should):

``` ruby
require 'tuktuk'

Tuktuk.options = {
  :dkim => {
    :domain => 'yoursite.com',
    :selector => 'mailer',
    :private_key => IO.read('ssl/yoursite.com.key')
  }
}

message = { ... }

response, email = Tuktuk.deliver(message)
```

For DKIM to work, you need to set up a TXT record in your domain's DNS.

Additional Tuktuk options:

``` ruby
Tuktuk.options = {
  :log_to => 'log/mailer.log',
  :helo_domain => 'mydomain.com',
  :max_workers => 'auto', # spawns a new thread for each domain, when delivering multiple
  :dkim => { ... }
}
```

Using with Rails
----------------

Tuktuk comes with ActionMailer support out of the box. In your environment.rb or environments/{env}.rb:

``` ruby
require 'tuktuk/rails'

[...]

config.action_mailer.delivery_method = :tuktuk

```

Since Tuktuk delivers email directly to the user's MX servers, it's probably a good idea to set `config.action_mailer.raise_delivery_errors` to true. That way you can actually know if an email couldn't make it to its destination.

When used with ActionMailer, you can pass options to Tuktuk also when setting the delivery method, like this:

``` ruby

options 

config.action_mailer.delivery_method = :tuktuk, {
  :log_to => 'log/mailer.log', # when not set, Tuktuk will use Rails.logger
  :dkim => {
    :domain => 'yoursite.com',
    :selector => 'mailer',
    :private_key => IO.read('ssl/yoursite.com.key')
  }
}

```

--

(c) 2013 Fork Limited. MIT license.
