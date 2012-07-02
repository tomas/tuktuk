Tuktuk - SMTP client for Ruby
=============================

Unlike Pony (which is friggin' awesome by the way) Tuktuk does not rely on 
`sendmail` or a separate SMTP server in order to send email. Tuktuk looks up the
MX servers of the destination address and connects directly using Net::SMTP. 
This way you don't need to install Exim or Postfix and you can actually handle 
response status codes -- like bounces, 5xx -- within your application. 

Plus, it supports DKIM out of the box.

``` ruby
  require 'tuktuk'

  email = {
    :from => 'you@username.com',
    :to => 'user@yoursite.com',
    :body => 'Hello there',
    :subject => 'Hiya'
  }

  Tuktuk.deliver(email)
```

To enable DKIM:

``` ruby
  require 'tuktuk'

  Tuktuk.options = {
    :dkim => {
      :domain => 'yoursite.com',
      :selector => 'mailer',
      :private_key => IO.read('ssl/yoursite.com.key')
    }
  }

  email = {
    :from => 'you@username.com',
    :to => 'user@yoursite.com',
    :body => 'Hello there',
    :subject => 'Hiya'
  }

  Tuktuk.deliver(email)
```

Additional options:

``` ruby
  Tuktuk.options = {
    :log_to => 'log/mailer.log',
    :max_attempts => 5,
    :retry_sleep => 10,
    :dkim => { ... }
  }
```

That's all.

--

(c) 2012 Fork Limited. MIT license.
