# -*- encoding: utf-8 -*-
require File.expand_path("../lib/tuktuk/version", __FILE__)

Gem::Specification.new do |s|
  s.name        = "tuktuk"
  s.version     = Tuktuk::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Tomás Pollak']
  s.email       = ['tomas@forkhq.com']
  s.homepage    = "https://github.com/tomas/tuktuk"
  s.summary     = "SMTP client for Ruby with DKIM support."
  s.description = "Easy way of sending DKIM-signed emails from Ruby, no depenencies needed."

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "tuktuk"

  s.add_development_dependency "bundler", ">= 1.0.0"
  s.add_runtime_dependency "net-dns", "= 0.6.1"
  s.add_runtime_dependency "mail", "~> 2.3"
  s.add_runtime_dependency "dkim", "~> 0.0.2"

  s.files        = `git ls-files`.split("\n")
  s.executables  = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'
end
