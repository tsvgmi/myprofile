#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vimfilt.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: vimfilt.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
=begin rdoc
=NAME
vimfilt.rb - VIM miscellaneous filter

=SYNOPSIS

=DESCRIPTION
This script implements various vi/vim filter used in development.  This
is preferable to writing filter in VIM scripting language (this works
for other editors as well).  This allows creating common filter script
which could be used with many editors.

=end

require File.dirname(__FILE__) + "/../etc/toolenv"
require 'csv'
require 'yaml'
require 'xmlhasher'
require 'cgi'
require 'mtool/core'

class ExportSet
  attr_reader :dset

  def initialize(file, options={})
    @file    = file
    @options = options
    @dset    = self.load
  end
end

class LastPassExport < ExportSet
  def load
    fields = nil
    result = {}
    CSV.foreach(@file) do |row|
      if fields
        next if (row.size < 5)
        row = row.map{|e| e ? CGI.unescapeHTML(e) : nil}
        rec = Hash[fields.zip(row)]
        key = "#{rec['name']} #{rec['username']}"
        result[key] = rec
      else
        fields = row
      end
    end
    result
  end

  def check_dups
    hasdups = false
    @dset.each do |name, dentry|
      next unless name =~ /Generated Password for /
      sname = $'
      if sentry = @dset[sname]
        STDERR.puts "*** Multiple entries found for #{sname}"
        STDERR.puts({type:"sentry", sentry:sentry}.inspect)
        STDERR.puts({type:"dentry", dentry:dentry}.inspect)
        hasdups = true
      end
    end
    hasdups
  end

  def check_nouser
    nouser = false
    @dset.each do |name, dentry|
      next if dentry['username']
      STDERR.puts "*** No username found for #{name}"
      STDERR.puts({type:"dentry", dentry:dentry}.inspect)
      nouser = true
    end
    nouser
  end
end

class MacPassExport < ExportSet
  def load
    entries = XmlHasher.parse(File.read(@file))[:KeePassFile][:Root][:Group]
    result  = {}
    entries[:Entry].each do |r|
      #STDERR.puts(r.to_yaml)
      rec = Hash[r[:String].map {|e|
        [e[:Key].downcase, e[:Value]]
      }]
      key = "#{rec['title']} #{rec['username']}"
      result[key] = rec
    end
    entries[:Group].select{|g| g[:Entry]}.each do |agroup|
      #STDERR.puts(agroup.to_yaml)
      entries = agroup[:Entry]
      unless entries.is_a?(Array)
        entries = [entries]
      end
      entries.each do |r|
        next unless r[:String]
        rec = Hash[r[:String].map {|e|
          [e[:Key].downcase, e[:Value]]
        }]
        key = "#{rec['title']} #{rec['username']}"
        result[key] = rec
      end
    end
    result
  end
end

class MacPass
  extendCli __FILE__

  def self.compare_to_lastpass(mpfile, lpfile)
    mpdata = MacPassExport.new(mpfile).dset
    lpdata = LastPassExport.new(lpfile).dset
    lpdata.each do |name, lpentry|
      name = name.sub(/Generated Password for /, '')
      if mprec = mpdata[name]
        if mprec['password'] != lpentry['password']
          STDERR.puts("***** #{name} has change in password - mp:#{mprec['password']} lp:#{lpentry['password']}")
          STDERR.puts(lpentry.to_yaml)
        end
      elsif lpentry['username']
        STDERR.puts("***** #{name} not found in macpass")
        STDERR.puts(lpentry.inspect)
      end
    end
    true
  end

  def self.lastpass_load(lpfile)
    LastPassExport.new(lpfile).dset.to_yaml
  end

  def self.lastpass_check_dups(lpfile)
    LastPassExport.new(lpfile).check_dups
  end

  def self.lastpass_check_nouser(lpfile)
    LastPassExport.new(lpfile).check_nouser
  end

  def self.macpass_load(mpfile)
    MacPassExport.new(mpfile).dset.to_yaml
  end
end

if (__FILE__ == $0)
  MacPass.handleCli(["--enscript", "-e"],
                    ["--type",     "-t"])
end


