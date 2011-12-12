#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: itunehelp.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'fileutils'
require 'mtool/core'

class LyricSource
  extendCli __FILE__

  LySource = {
    'justsome' => {
      :base => "http://www.justsomelyrics.com",
      :src  => "http://www.google.com/cse?cx=000975271163936304601%3Ao53s1ouhhyy&q=%TITLE%&sa=Search&cof=FORID%3A0&siteurl=www.justsomelyrics.com%2F#gsc.tab=0&gsc.q=%TITLE%&gsc.page=1"
    },
    'video4viet' => {
      :base => "http://www.video4viet.com",
      :src  => "http://www.video4viet.com/lyrics.html?act=search&q=%TITLE%&type=title"
    },
    'yeucahat' => {
      :base => "http://search.yeucahat.com",
      :src  => "http://search.yeucahat.com/search.php?s=%TITLE%&mode=title"
    },
    'zing' => {
      :base => "http://mp3.zing.vn",
      :src  => "http://mp3.zing.vn/tim-kiem/bai-hat.html?q=%TITLE%&filter=4"
    },
    'console' => {}
  }

  def self.get(src, options = {})
    case src
    when 'video4viet'
      LyVideo4Viet.new(src, options)
    when 'yeucahat'
      LyYeuCaHat.new(src, options)
    when 'zing'
      LyZing.new(src, options)
    when 'justsome'
      LyJustSome.new(src, options)
    else
      LyricSource.new(src, options)
    end
  end

  def initialize(src, options = {})
    @source  = src
    @options = options
    @config  = LySource[src]
    raise "Lyrics source #{@source} not found" unless @config
  end

  protected
  def to_clean_ascii(string)
    string.vnto_ascii.sub(/\s*[\-\(].*$/, '').
                       gsub(/\'/, " ").downcase
  end

  def fetch_hpricot(url)
    require 'hpricot'
    if false
      require 'open-uri'

      Plog.info "Fetching from #{url}"
      fid   = open(url)
      pg    = Hpricot(fid.read)
      fid.close
      pg
    else
      Plog.info "Fetching #{url}"
      Hpricot(`curl --silent -A Mozilla/4.0 "#{url}"`)
    end
  end

  public
  def page_url(name)
    require 'uri'

    @config[:src].gsub(/%TITLE%/, URI.escape(to_clean_ascii(name)))
  end

  # Get and parse manually
  # 
  # Default does not do auto.  Ask user to paste it in
  # @param [ITuneTrack] track
  def manual_get(track)
    case @source
    when 'console'
    else
      Pf.system("open --background '#{self.page_url(track.name)}'", 1)
    end
    STDOUT.puts "Enter content for lyrics [ = to end]: "
    content = []
    while line = STDIN.gets.chomp
      break if line =~ /^=/
      content << line
    end
    result = content.join("\n").strip
  end

  def auto_get(track)
    manual_get(track)
  end

  def extract_metadata(lyrics)
    cn    = lyrics.split(/[\r\n]+/)
    title = cn[0].strip
    unless title.empty?
      return {:name=>title}
    else
      return {}
    end
  end
end

class LyVideo4Viet < LyricSource
  def auto_get(track)
    cname   = to_clean_ascii(track.name)
    cartist = to_clean_ascii(track.artist)
    pg      = fetch_hpricot(self.page_url(track.name))
  end

  def extract_metadata(lyrics)
    cn    = lyrics.split(/[\r\n]+/)
    chset = {}
    title = cn[0].strip
    if (cn[1] =~ /:\s*/)
      chset[:name]     = title unless title.empty?
      chset[:composer] = $'.sub(/\s*[-\(;].*$/, '')
    else
      Plog.error "#{@kname}. Lyrics not in valid form"
    end
    chset
  end
end

class LyYeuCaHat < LyricSource
  def auto_get(track)
    cname   = to_clean_ascii(track.name)
    cartist = to_clean_ascii(track.artist)
    pg      = fetch_hpricot(self.page_url(track.name))
    tb0 = pg.search("//table.forumline")[0]
    (tb0.search("//tr.row1") + tb0.search("//tr.row2")).each do |arow|
      aref  = arow.at("//a.topictitle")
      wname = to_clean_ascii(aref.inner_text)
      next unless (wname == cname)
      wartist = to_clean_ascii(File.basename(href).sub(/^.*~/, '').
              sub(/\.html$/, '').gsub(/-/, ' '))
      if (wartist == cartist)
        return extract_text(track.name, aref['href'])
      else
        ccomposer = to_clean_ascii(track.composer)
        cref      = arow.search("//span.gensmall")[1]
        wcomposer = to_clean_ascii(cref.children[3])
        Plog.info "Found composer #{wcomposer}" if @options[:verbose]
        if (wcomposer == ccomposer)
          return extract_text(track.name, aref['href'])
        end
      end
    end
    ""
  end

  def extract_text(title, href)
    pg    = fetch_hpricot(@config[:base] + "/#{href}")
    title = pg.search("//span.maintitle").inner_text
    meta  = pg.search("//span.genmed")[1].inner_text.strip
    lyric = pg.search("//span.lyric").inner_text.strip
    if lyric.empty?
      ""
    else
      title + "\n" + meta + "\n" + lyric + "\n" + href
    end
  end

  def extract_metadata(lyrics)
    cn    = lyrics.split(/[\r\n]+/)
    chset = {}
    title = cn[0].strip
    1.upto(2) do |idx|
      next if cn[idx] =~ /^Ca /
      if (cn[idx] =~ /:\s*/)
        chset[:name]     = title unless title.empty?
        value = $'.sub(/\s*[-\(;].*$/, '')
        if value !~ /^Album/
          chset[:composer] = value
        end
        break
      end
    end
    chset
  end
end

class LyZing < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def auto_get(track)
    cname   = to_clean_ascii(track.name)
    cartist = to_clean_ascii(track.artist)
    pg      = fetch_hpricot(self.page_url(track.name))
    pg.search("//a.f142").each do |ele|
      title, wartist = ele['title'].split(/\s*-\s*/)
      wname = to_clean_ascii(title)
      next unless (wname == cname)
      wartist = to_clean_ascii(wartist)
      if (wartist == cartist)
        return extract_text(title, ele['href'])
      end
    end
    ""
  end

  def extract_text(title, href)
    pg    = fetch_hpricot(@config[:base] + "/#{href}")
    lyric = pg.search("//p._lyricContent").inner_text.strip
    if lyric.empty?
      ""
    else
      title + "\n" + lyric + "\n" + href
    end
  end

  def extract_metadata(lyrics)
    cn    = lyrics.split(/[\r\n]+/)
    chset = {}
    title = cn[0].strip
    if (cn[1] =~ /:\s*/)
      chset[:name]     = title unless title.empty?
      chset[:composer] = $'.sub(/\s*[-\(;].*$/, '')
    else
      Plog.error "#{@kname}. Lyrics not in valid form"
    end
    chset
  end
end

class LyJustSome < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def auto_get(track)
    cname   = to_clean_ascii(track.name)
    cartist = to_clean_ascii(track.artist)
    pg      = fetch_hpricot(self.page_url(track.name))
    pg.search("//div/a").each do |ele|
      href      = ele['href']
      bname     = URI.unescape(File.basename(href))
      checklink = bname.sub(/-lyrics$/i, '').vnto_ascii.downcase.gsub(/-/, ' ')
      if @options[:verbose]
        Plog.info "Check for [#{bname}] #{checklink}/#{cname}/#{cartist}"
      end
      if (checklink =~ /#{cname}/) && (checklink =~ /#{cartist}/)
        return extract_text(track.name, ele['href'])
      end
    end
    ""
  end

  def extract_text(title, href)
    pg    = fetch_hpricot(href)
    lyric = pg.search("//center").inner_text.strip
    if lyric.empty?
      ""
    else
      lyric = lyric.gsub(/^.*to your Cell/, '').
        gsub(/^cf_.*$/, '').
        gsub(/\n+/m, "\n")
      title + "\n" + lyric
    end
  end

  def extract_metadata(lyrics)
    {}
  end
end
if (__FILE__ == $0)
  LyricSource.handleCli
end
