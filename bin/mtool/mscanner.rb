#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: mscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'mtool/core'
require 'rubygems'
require 'fileutils'
require 'tempfile'
require 'hpricot'
require 'open-uri'
require 'active_record'

SITES = YAML.load <<EOF
vientay:
  :base_url: http://www.vientay.com/f
  :fdmask:   http://www.vientay.com/f/f%FOLDER%/i%PAGE%.html
  :tpmask:   http://www.vientay.com/f/f%FOLDER%/%EURL%
  :encode:   VISCII
  :map:
    app:     9
    amovie:  105
    fmovie:  104
    fmusic:  122
    karaoke: 207
    kseries: 111
    vmovie:  106
    vmusic:  120
vncentral:
  :base_url: http://forums.vncentral.com
  :map:
    video: 8
    vmusic: 9
hadung:
  :base_url: http://www.hadung.net
  :map:
    desktop: Applications/desktop-enhancements
EOF

class ActiveRecord::Base
  def save_wait
    countdown = 5
    while countdown > 0
      countdown -= 1
      begin
        return self.save
      rescue SQLite3::BusyException
        sleep 1
        Plog.warn "Retry ..."
      end
    end
  end
end

class DbAccess
  @@_dbinstance = nil
  def self.instance
    unless @@_dbinstance
      ActiveRecord::Base.establish_connection(
        :adapter  => 'sqlite3',
        :database => "mscanner.db"
      )
      @@_dbinstance = ActiveRecord::Base.connection
    end
    @@_dbinstance
  end
end

class PhpTopic < ActiveRecord::Base
  has_many :php_urls
end

class PhpUrl < ActiveRecord::Base
  belongs_to :php_topic
end

class PhpForum

  def initialize(name, config, options = {})
    @name     = name
    @config   = config
    @base_url = config[:base_url]
    @options  = options
    @rmap     = {}
    config[:map].each do |folder, fvalue|
      @rmap[fvalue] = folder
    end
  end

  def topic_of(thread)
    PhpTopic.find(:first,
      :conditions=>["site=? and thread=?", @name, thread]);
  end

  def self.translit(str, encode)
    begin
      str = Iconv.iconv('UTF-8//IGNORE//TRANSLIT', encode, str).to_s
    rescue Iconv::IllegalSequence, Iconv::InvalidCharacter => errmsg
      p errmsg
      str = str.gsub(/[^&a-z._0-9 -]/i, "").tr(".", "_")
    end
    str = str.gsub(/&#\d+;/) {|p| entitymap(p)}
    #str = Iconv.iconv('ASCII//IGNORE//TRANSLIT', 'UTF-8', str).to_s
  end

  def print(folder_name, spage = 1)
    limit = (@options[:limit] || 300).to_i
    if folder_name == '-'
      conditions = ["site=? and page>=?", @name, spage]
    else
      folder = @config[:map][folder_name]
      raise "No folder #{folder_name} found for #{@name}" unless folder
      conditions = ["site=? and folder=? and page>=?", @name, folder, spage]
    end
    PhpTopic.find(:all, :conditions=>conditions, :order=>"thread desc",
        :limit=>limit).each do |item|
      if encoding = @config[:encode]
        title = PhpForum.translit(item.title, encoding)
      else
        title = item.title
      end
      #title = Iconv.iconv('ASCII//IGNORE//TRANSLIT', 'UTF-8', title).to_s
      puts "%8s | %6d | %s | %3d | %s" % ["#{item.folder}.#{item.page}",
        item.thread, item.created.strftime("%m/%d/%y"), item.php_urls.size,
        title]
    end
    true
  end

  def list_folders
    @config[:map].keys
  end

  def self.entitymap(string)
    value = string[2..-1].to_i
    if value <= 127
      out = "%c" % [value]
    elsif value <= 2047
      out = "%c%c" % [
        ((value >> 6) & 0x1f)  + 0xc0,
        (value & 0x3f) + 0x80
      ]
    elsif value <= 65535
      out = "%c%c%c" % [
        ((value >> 12) & 0xf) + 0xe0,
        ((value >> 6) & 0x3f) + 0x80,
        (value & 0x3f) + 0x80
      ]
    else
      out = "%c%c%c%c" % [
        ((value >> 18) & 0x7) + 0xf0,
        ((value >> 12) & 0x3f) + 0x80,
        ((value >> 6) & 0x3f) + 0x80,
        (value & 0x3f) + 0x80
      ]
    end
    out
  end

  def scan_file(file)
    Plog.info "Scanning #{file}"
    doc     = Hpricot(File.read(file))
    folder  = file.split(/[-.]/)[1]
    page    = file.split(/[-.]/)[2]
    newlist = []
    doc.search("//a[@id]").each do |elem|
      href = elem['href']
      thread = nil
      if href =~ /showthread.php.*t=(\d+)/
        eurl   = nil
        thread = $1
      elsif href =~ /\/f\/f\d+\/(.*.html)/
        eurl = $1
        if eurl =~ /-(\d+)\.html$/
          thread = $1
        end
      end
      if thread
        title = elem.inner_html.strip
        rec   = topic_of(thread)
        unless MsScanner.getOption(:force)
          next if rec
        end
        unless rec
          rec = PhpTopic.new(:site=>@name, :thread=>thread, :eurl=>eurl)
        end
        rec.folder  = folder.to_i
        rec.page    = page.to_i
        rec.title   = title
        rec.created = Time.now
        rec.save_wait
        newlist << rec
      end
    end
    newlist
  end

  def scan_new(folder_name)
    apage, end_page = 1, 1000
    hasnew = false
    folder = @config[:map][folder_name]
    fdmask = @config[:fdmask]
    Plog.info "Process #{folder_name}:#{folder}"
    raise "No folder #{folder_name} found for #{@name}" unless folder
    while true
      ofile = "#{@name}-#{folder}-#{apage}.html"
      Plog.info("Reading page #{apage} to #{ofile}")
      if fdmask
        rurl = fdmask.gsub(/%FOLDER%/, folder.to_s).
                      gsub(/%PAGE%/, apage.to_s)
      else
        rurl = "#{@base_url}/forumdisplay.php?f=#{folder}&page=#{apage}"
      end
      #p rurl
      fid = open(rurl)
      page = fid.read
      fid.close

      fod = File.open(ofile, "w")
      fod.puts(page)
      fod.close
      
      if scan_file(ofile).size > 0
        hasnew = true
        apage += 1
        if apage > end_page
          Plog.info("Pass last page")
          break
        end
      else
        Plog.info("Don't find anything new")
        break
      end
    end
    hasnew
  end

  def scan_topic(topic, webopen = false)
    tfile = "t#{topic}.html"
    record = topic_of(topic)
    unless record
      Plog.error "No record found for #{@name}-#{topic}"
      return false
    end
    hrefs = record.php_urls
    
    tpmask  = @config[:tpmask]
    if tpmask
      eurl = tpmask.gsub(/%FOLDER%/, record.folder.to_s).
        gsub(/%PAGE%/, record.page.to_s).
        gsub(/%EURL%/, record.eurl)
    else
      eurl = "#{@base_url}/showthread.php?t=#{topic}"
    end
    Plog.info "#{eurl}"
    if webopen
      Pf.system "open '#{eurl}'"
    end
    unless MsScanner.getOption(:force)
      if hrefs && (hrefs.size > 0)
        return hrefs.map{|r| r.url}
      end
    end
    if !test(?f, tfile)
      fid = open(eurl)
      fod = File.open(tfile, "w")
      fod.puts(fid.read)
      fid.close
      fod.close
    end
    doc = Hpricot(File.open(tfile))
    hrefs = []
    ptn = Regexp.new(/(calihub|imagegethost|luyenphim|quote|seeker|shareapic|skincare|vietnamair|vndragons|vnpapaya|waretopia|xalovietnam|xaloweb)/)
    doc.search("//a").each do |elem|
      href = elem['href']
      next unless (href =~ /http:/i)
      next if (href =~ /#{@name}/i)
      next if ptn.match(href)
      next if (href =~ /(gif|jpg)$/i)
      hrefs << href
    end
    hrefs = hrefs.select {|url| url !~ /(\.com\/?$|phimhong)/ }
    hrefs.each do |url|
      p url
      record.php_urls.create(:url => url)
    end
    hrefs
  end
end

# Helper for vnc script.
class MsScanner
  extendCli __FILE__

  def self.forum_site(name)
    fdata = SITES[name]
    PhpForum.new(name, fdata, getOption)
  end

  # Scan for any new pages or topics
  def self.scan_new(forum, fname = 'vmusic')
    DbAccess.instance
    dbase  = forum_site(forum)
    SITES[forum][:map].each do |k, v|
      dbase.scan_new(k)
    end
  end

  # Scan a downloaded page file.  Not used normally
  def self.scan_file(forum, *files)
    DbAccess.instance
    dbase  = forum_site(forum)
    hasnew = false

    files.each do |file|
      if dbase.scan_file(file).size > 0
        hasnew = true
      end
    end
    hasnew
  end

  def self.print(forum, fname = 'vmusic')
    DbAccess.instance
    forum_site(forum).print(fname)
  end

  def self.list_folders(forum)
    DbAccess.instance
    forum_site(forum).list_folders
  end

  # Scan the topic content for links
  def self.scan_topic(forum, topic)
    DbAccess.instance
    forum_site(forum).scan_topic(topic, getOption(:open))
  end

end

if (__FILE__ == $0)
  MsScanner.handleCli(
        ['--open',  '-o', 0],
        ['--force', '-f', 0],
        ['--limit', '-l', 1]
  )
end

=begin
sqlite3 mscanner.db

create table php_topics (
  id integer primary key autoincrement,
  site string,
  folder integer,
  page integer,
  thread integer,
  eurl varchar,
  title varchar,
  created datetime
);
create unique index topicidx1 on php_topics(site,thread);

create table php_urls (
  id integer primary key autoincrement,
  php_topic_id integer,
  url varchars
);
create index urlidx1 on php_urls(php_topic_id);
=end
