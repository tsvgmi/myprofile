#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require File.dirname(__FILE__) + "/../etc/toolenv"
require 'nokogiri'
require 'csv'
require 'yaml'
require 'mtool/core'

module Utils
  def clean_url(url)
    url = url.sub(%r{https?://([^/]+)/?.*$}io, '\\1').sub(/^www\./io, '')
    comp = url.split('.')
    comp.size >= 2 ? comp[-2..-1].join('.') : nil
  end

  def ls
    @entries.keys.sort.each do |url|
      entry = @entries[url]
      puts "%-40s %-20s %-12s %s" %
        [url, entry[:user], entry[:password], entry[:group]]
    end
    true
  end
end

class KeyPassXml
  include Utils

  attr_accessor :entries

  def initialize(kpfile)
    require 'nokogiri'

    @kpfile = kpfile
    _parse
    @add_store  = {}
  end

  def _parse
    if @kpfile =~ /.gpg$/
      command  = "gpg < #{@kpfile}"
      fid      = File.popen(command, "r")
    else
      fid      = File.open(@kpfile, "r")
    end
    @doc     = Nokogiri::XML(fid.read)
    @entries = {}
    @groups  = []
    @doc.css('Group').each do |agroup|
      group = agroup.css('Name')[0].text
      agroup.css('Entry').each do |entry|
        hentry = {group: group}
        @groups << group unless @groups.include?(group)
        entry.css('String').each do |astring|
          key = astring.css('Key').text
          val = astring.css('Value').text
          hentry[key] = val
        end
        key  = clean_url(hentry['URL'])
        user = hentry['UserName'].strip
        next unless key
        @entries[key] ||= {}
        @entries[key][user] = {
          url:      hentry['URL'].strip,
          user:     user,
          password: hentry['Password'].strip,
          group:    hentry[:group]
        }
      end
    end
  end

  def add_if_missing(url, entry)
    if match = @entries[url]
      if (match[:username] == entry[:username]) &&
         (match[:password] == entry[:password])
        Plog.dump_info(msg:"Existing", url:url)
        return
      end
    end
    Plog.dump_info(msg:"Adding", group:@groups[0], url:url, entry:entry.keys)
    @add_store[entry[:group]] ||= []
    @add_store[entry[:group]] << {
      url:      entry[:url],
      user:     entry[:user],
      password: entry[:password],
    }
  end
   
  def save_store(ofile)
    File.open(ofile, "w") do |fod|
      fod.puts @add_store.to_yaml
    end
    Plog.info "Missing entries saved to #{ofile}"
  end
end

class LastPassFile
  include Utils

  attr_accessor :entries

  def initialize(lpfile)
    require 'csv'

    @lpfile  = lpfile
    if @lpfile =~ /.gpg$/
      command = "gpg < #{lpfile}"
      fid     = File.popen(command, "r")
    else
      fid     = File.open(@lpfile)
    end
    rows     = CSV.parse(fid.read)
    fid.close
    cols     = rows.shift
    @entries = {}
    @groups  = []
    rows.each do |arow|
      crow  = Hash[cols.zip(arow)]
      key   = clean_url(crow['url'])
      next unless key
      group = crow['grouping']
      user  = (crow['username'] || '').strip
      @groups << group unless @groups.include?(group)
      @entries[key] ||= {}
      @entries[key][user] = {
        url:      crow['url'],
        user:     user,
        password: (crow['password'] || '').strip,
        group:    group
      }
    end
  end
end

class LPSync
  extendCli __FILE__

  class << self
    def list_lp(lpfile)
      LastPassFile.new(lpfile).ls
    end

    def list_kp(kpfile)
      KeyPassXml.new(kpfile).ls
    end

    def compare(kpfile, lpfile)
      require 'yaml'

      options    = getOption
      kp_entries = KeyPassXml.new(kpfile).entries
      lp_entries = LastPassFile.new(lpfile).entries
      sites      = (kp_entries.keys + lp_entries.keys).sort.uniq
      cb_entries = {}
      target     = options[:target] ? options[:target].to_sym : nil
      sites.each do |asite|
        next if asite =~ /^[\d\.:]+$/
        lpe = lp_entries[asite]
        kpe = kp_entries[asite]
        #if lpe && kpe && (lpe[0][:user] == kpe[0][:user]) && (lpe[0][:password] == kpe[0][:password])
          #next
        #end
        if target
          next if target == :kp && lpe
          next if target == :lp && lpe
        end
        cb_entries[asite] = {lp:lpe, kp:kpe}
      end
      cb_entries.to_yaml
    end

    def add_kp_missing(kpfile, lpfile, ofile)
      lastpass = LastPassFile.new(lpfile)
      keypass  = KeyPassXml.new(kpfile)
      lastpass.entries.each do |url, entry|
        keypass.add_if_missing(url, entry)
      end
      keypass.save_store(ofile)
      true
    end
  end
end

if (__FILE__ == $0)
  LPSync.handleCli(
    ['--auth',         '-a', 1],
    ['--check_lyrics', '-k', 0],
    ['--limit',        '-l', 1],
    ['--ofile',        '-o', 1],
    ['--target',       '-t', 1],
    ['--exclude_user', '-x', 1],
  )
end
