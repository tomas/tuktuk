Tuktuk - SMTP client for Ruby
=============================

Unlike famous ol' Pony gem (which is friggin' awesome by the way), Tuktuk does not rely on 
`sendmail` or a separate SMTP server in order to deliver email. Tuktuk looks up the
MX servers of the destination address and connects directly using Net::SMTP. 
This way you don't need to install Exim or Postfix and you can actually handle 
response status codes -- like bounces, 5xx -- within your application. 

Plus, it supports DKIM out of the box.

Delivering mail
---------------

``` ruby
require 'tuktuk'

message = {
  :from    => 'you@username.com',
  :to      => 'user@yoursite.com',
  :body    => 'Hello there',
  :subject => 'Hiya'
}

response, email = Tuktuk.deliver(message)
```

HTML (multipart) emails are supported, of course. 

``` ruby

message = {
  :from      => 'you@username.com',
  :to        => 'user@yoursite.com',
  :body      => 'Hello there',
  :html_body => '<h1 style="color: red">Hello there</h1>',
  :subject   => 'Hiya in colours'
}

response, email = Tuktuk.deliver(message)
```

The `response` is either a [Net::SMTP::Response](http://ruby-doc.org/stdlib-2.0.0/libdoc/net/smtp/rdoc/Net/SMTP/Response.html) object, or a Bounce exception (HardBounce or SoftBounce, depending on the cause). `email` is a [mail](https://github.com/mikel/mail) object. So, to handle bounces you'd do:

``` ruby
[...]

response, email = Tuktuk.deliver(message)

if response.is_a?(Tuktuk::Bounce)
  puts 'Email bounced. Type: ' + response.class.name # => HardBounce or SoftBounce
else
  puts 'Email delivered! Server responded: ' + response.message
end
```

You can also call `Tuktuk.deliver!` (with a trailing `!`), in which case it will automatically raise an exception if the response was either a `HardBounce` or a `SoftBounce`. This is useful when running in the background via Resque or Sidekiq, because it makes you aware of which emails are not getting through, and you can requeue those jobs to have them redelivered.

Email options
-------------

Attachments are supported, as you'd expect. 

``` rb
message = {
  :from             => 'john@lennon.com',
  :to               => 'paul@maccartney.com',
  :subject          => 'Question for you',
  :body             => 'How do you sleep?',
  :reply_to         => '<haha@foobar.com>',
  :return_path      => 'bounces@server.com',
  :attachments      => [ '/home/john/walrus.png' ]
}
```

Attachments can be either a path to a file or a hash containing the file's name and content, like this:

``` rb
  message = {
    ...
    :attachments => [ 
      { :filename => 'walrus.png', :content => File.read('/home/john/walrus.png') } 
    ]
  }
```

These are the email headers Tuktuk is able to set for you. Just pass them as part of the hash and they'll be automatically set.

```
  :return_path      => '<return-path@host.com>', # will actually set three headers, Return-Path, Bounces-To and Errors-To
  :reply_to         => '<reply@to.com>',
  :in_reply_to      => '<inreply@to.com>',
  :list_unsubscribe => '<http://server.com/path>, <mailto:somewhere@server.com>',
  :list_archive     => '<http://server.com/list/archive>',
  :list_id          => '<mail-list.foobar.com>'
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

  if response.is_a?(Tuktuk::Bounce)
    puts 'Email bounced. Type: ' + response.class.name
  else
    puts 'Email delivered!'
  end

end
```

Options & DKIM
--------------

Now, if you want to enable DKIM (and you _should_):

``` ruby
require 'tuktuk'

Tuktuk.options = {
  :dkim => {
    :domain      => 'yoursite.com',
    :selector    => 'mailer',
    :private_key => IO.read('ssl/yoursite.com.key')
  }
}

message = { ... }

response, email = Tuktuk.deliver(message)
```

For DKIM to work, you need to set up some TXT records in your domain's DNS. You can use [this tool](http://www.socketlabs.com/domainkey-dkim-generation-wizard/) to generate the key. You should also create [SPF records](http://www.spfwizard.net/) if you haven't. Then use [this tool](https://www.mail-tester.com/spf-dkim-check) to verify that they're both correctly in place.

All available options, with their defaults:

``` ruby
Tuktuk.options = {
  :log_to       => nil,   # e.g. log/mailer.log or STDOUT
  :helo_domain  => nil,   # your server's domain goes here
  :max_workers  => 0,     # controls number of threads for delivering_many emails (read below)
  :open_timeout => 20,    # max seconds to wait for opening a connection
  :read_timeout => 20,    # 20 seconds to wait for a response, once connected
  :verify_ssl   => true,  # whether to skip SSL keys verification or not
  :debug        => false, # connects and delivers email to localhost, instead of real target server. CAUTION!
  :dkim => { ... }
}
```

You can set the `max_workers` option to `auto`, which will spawn the necessary threads to connect in paralell to all target MX servers when delivering multiple messages. When set to `0`, these batches will be delivered sequentially.

In other words, if you have three emails targeted to Gmail users and two for Hotmail users, using `auto` Tuktuk will spawn two threads and connect to both servers at once. Using `0` will have your emails delivered to one host, and then the other.

Using with Rails
----------------

Tuktuk comes with ActionMailer support out of the box. In your environment.rb or environments/{env}.rb:

``` ruby
require 'tuktuk/rails'

[...]

config.action_mailer.delivery_method = :tuktuk
```

Since Tuktuk delivers email directly to the user's MX servers, it's probably a good idea to set `config.action_mailer.raise_delivery_errors` to true. That way you can actually know if an email couldn't make it to its destination.

When used with ActionMailer, you can pass options using ActionMailer's interface, like this:

``` ruby

config.action_mailer.delivery_method = :tuktuk

config.action_mailer.tuktuk_settings = {
  :log_to => 'log/mailer.log', # when not set, Tuktuk will use Rails.logger
  :dkim => {
    :domain      => 'yoursite.com',
    :selector    => 'mailer',
    :private_key => IO.read('ssl/yoursite.com.key')
  }
}
```

# Contributions

You're more than welcome. Send a pull request, including tests, and make sure you don't break anything. That's it.

# Copyright

(c) Fork Limited. MIT license.
