#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: webpass.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'mtool/core'
require 'digest/sha1'
require 'yaml'
require 'base64'

class WebPass
  extendCli __FILE__

  CFILE  = "#{ENV['HOME']}/.tool/webpass.yml"

  def initialize(cfile)
    if test(?f, CFILE)
      @config = YAML.load_file(CFILE)
    end
  end

  def verify(*args)
    newmaster = Digest::SHA1.hexdigest(args.join(' '))
    newmaster == @config[:master]
  end

  def create(master, site, afilt = nil)
    unless verify(master)
      STDERR.puts "Master key verification failed"
      return false
    end
    msite   = site.sub(/^https?:\/\//i, '').sub(/[\/\?].*$/, '')
    hpasswd = Digest::SHA512.hexdigest("#{msite}+#{master}")
    passwd  = Base64.encode64(hpasswd)
    #afilt   = @config[:sites][msite]
    #p passwd[0..9]
    case afilt
    when 'U'            ## Upper case only
      passwd = passwd.upcase
    when 'P'            ## Add a puntuation
      passwd[0] = ','
    when '0'            ## Add a number
      passwd[0] = '7'
    when /M/            ## Mixed case
      if afilt =~ /M[13]/
        passwd[0] = ','
      end
      if afilt =~ /M[23]/
        passwd[1] = '7'
      end
      state  = 0
      result = ""
      passwd.split('').each do |c|
        case state
        when 0
          if c =~ /[A-Za-z]/
            c = c.upcase
            state = 1
          end
        when 1
          if c =~ /[A-Za-z]/
            c = c.downcase
            state = 2
          end
        end
        result << c
      end
      passwd = result
    end
    passwd[0..9]
  end

  def self.create_master(*args)
    output = Digest::SHA1.hexdigest(args.join(' '))
    config = {
      :master => output,
      :sites  => {}
    }
    ofile  = CFILE
    fod    = File.open(ofile, "w")
    fod.puts config.to_yaml
    fod.close
  end

  def self.cliNew
    WebPass.new(CFILE)
  end
end

if (__FILE__ == $0)
  WebPass.handleCli
end


