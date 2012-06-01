Tuktuk - SMTP client for Ruby
=============================

````
  require 'tuktuk'

  email = {
    :from => 'you@username.com',
    :to => 'user@yoursite.com',
    :body => 'Hello there',
    :subject => 'Hiya'
  }

  Tuktuk.deliver(email)
````

To enable DKIM:

````
  require 'tuktuk'

  Tuktuk.dkim = {
      :domain => 'yoursite.com',
      :selector => 'mailer',
      :private_key => IO.read('ssl/yoursite.com.key')
  }

  email = {
    :from => 'you@username.com',
    :to => 'user@yoursite.com',
    :body => 'Hello there',
    :subject => 'Hiya'
  }

  Tuktuk.deliver(email)
````

That's all.

--

(c) 2012 Fork Limited. MIT license.
