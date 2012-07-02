Tuktuk - SMTP client for Ruby
=============================

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
