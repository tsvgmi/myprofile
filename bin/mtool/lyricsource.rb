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
require 'mtool/vnmap'

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
    # Javascript protected
    'yeucahat' => {
      :base => "http://search.yeucahat.com",
      :src  => "http://search.yeucahat.com/search.php?s=%TITLE%&mode=title"
    },
    'zing' => {
      :base => "http://mp3.zing.vn",
      :src  => "http://mp3.zing.vn/tim-kiem/bai-hat.html?q=%TITLE%"
    },
    # Javascript protected
    'vportal' => {
      :base => "http://http://vietnameseportal.com/",
      :src  => "http://vietnameseportal.com/cgi-bin/lyric/search.cgi?cx=014985440914852074501%3Asliobasbm7a&cof=FORID%3A11&query=%TITLE%&q=%TITLE%"
    },
    # Slow pace - 3-5 secs each
    'tkaraoke' => {
      :base => "http://lyric.tkaraoke.com",
      :src  => "http://lyric.tkaraoke.com/s.tim?q=%TITLE%&t=1"
    },
    'nhactui' => {
      :base => "http://www.nhaccuatui.com",
      :src  => "http://www.nhaccuatui.com/tim_kiem?q=%TITLE%"
    },
    'console' => {}
  }

  @@src_cache = {}
  def self.get(src, options = {})
    if @@src_cache[src]
      return @@src_cache[src]
    end
    @@src_cache[src] = case src
    when 'video4viet'
      LyVideo4Viet.new(src, options)
    when 'yeucahat'
      LyYeuCaHat.new(src, options)
    when 'zing'
      LyZing.new(src, options)
    when 'justsome'
      LyJustSome.new(src, options)
    when 'vportal'
      LyVPortal.new(src, options)
    when 'tkaraoke'
      LyTkaraoke.new(src, options)
    when 'nhactui'
      LyNhacTui.new(src, options)
    else
      LyricSource.new(src, options)
    end
  end

  attr_reader :skiplist

  def initialize(src, options = {})
    @source  = src || 'console'
    @options = options
    @config  = LySource[src]

    skipfile  = @source + ".yml"
    @skiplist = HashYaml.new(skipfile)
    @chset    = {}
    at_exit { @skiplist.save }
  end

  protected
  def to_clean_ascii(string, ignore = "-(")
    string.vnto_ascii.sub(/\s*[#{ignore}].*$/, '').
       gsub(/\'/, " ").gsub(/\s+/, ' ').
       gsub(/!/, "").downcase
  end

  def fetch_hpricot(url)
    require 'hpricot'

    Plog.info "Fetching #{url}"
    Pf.system("open -g '#{url}'", 1)
    Hpricot(`curl --silent -A Mozilla/4.0 "#{url}"`)
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
    @curtrack = track
    _auto_get(track)
  end

  def _auto_get(track)
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

  def confirm_text(lyrics)
    @curtrack.play
    puts @curtrack.name + "\n"
    puts lyrics
    Cli.confirm("OK to save this")
  end
end

class LyVideo4Viet < LyricSource
  def _auto_get(track)
    manual_get(track)
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
  def _auto_get(track)
    manual_get(track)
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
  def _auto_get(track)
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
      return ""
    end
    title + "\n" + lyric + "\n" + href
  end

  def extract_metadata(lyrics)
    cn    = lyrics.split(/[\r\n]+/)
    chset = {}
    title = cn[0].strip
    if (cn[1] =~ /:\s*/)
      chset[:name]     = title unless title.empty?
      comp =  $'.sub(/\s*[-\(;].*$/, '')
      unless comp.empty?
        chset[:composer] = comp
      end
    else
      Plog.error "#{@kname}. Lyrics not in valid form"
    end
    chset
  end
end

class LyJustSome < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def _auto_get(track)
    cname   = to_clean_ascii(track.name)
    cartist = to_clean_ascii(track.artist)
    pg      = fetch_hpricot(self.page_url(track.name))
    wlinks  = []
    pg.search("//div/a").each do |ele|
      href      = ele['href']
      bname     = URI.unescape(File.basename(href))
      checklink = bname.sub(/-lyrics$/i, '').vnto_ascii.downcase.gsub(/-/, ' ')
      if @options[:verbose]
        Plog.info "Check for [#{bname}] #{checklink}/#{cname}/#{cartist}"
      end
      if (checklink =~ /#{cname}/)
        if (checklink =~ /#{cartist}/)
          return extract_text(track.name, ele['href'])
        else
          wlinks << [track.name, ele['href']]
        end
      end
    end
    # Only 1 candidate, we take it also
    if wlinks.size > 0
      name, href = wlinks.first
      return extract_text(name, href, true)
    end
    ""
  end

  def extract_text(title, href, confirm = false)
    pg    = fetch_hpricot(href)
    lyric = pg.search("//center").inner_text.strip
    if lyric.empty?
      return ""
    end
    if confirm && !confirm_text(lyric)
      return ""
    end
    lyric = lyric.gsub(/^.*to your Cell/, '').
      gsub(/^cf_.*$/, '').
      gsub(/^.* LYRICS/, '').
      gsub(/\n+/m, "\n")
    title + "\n" + lyric
  end

  def extract_metadata(lyrics)
    chset = {}
    cn    = lyrics.split(/[\r\n]+/)
    cn.each do |aline|
      puts aline
      if aline =~ /(Composer|Sáng tác):\s*/
        p aline
        chset[:composer] = $'
      end
    end
    chset
  end
end

class LyVPortal < LyricSource
  def extract_metadata(lyrics)
    cn    = lyrics.split(/[\r\n]+/)
    chset = {}
    title, ns = cn[0].strip.split(/\s*-\s*/)
    if ns
      chset[:name]     = title unless title.empty?
      chset[:composer] = ns.sub(/^.*:\s+/, '')
    else
      Plog.error "#{@kname}. Lyrics not in valid form"
    end
    chset
  end
end

class LyTkaraoke < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def _auto_get(track)
    cname     = to_clean_ascii(track.name)
    cartist   = to_clean_ascii(track.artist)
    ccomposer = to_clean_ascii(track.composer)
    pg        = fetch_hpricot(self.page_url(track.name))
    matchset  = []
    pg.search("table.SResult//tr").each do |row|
      wfields = {}
      ['SongName', 'Singer', 'SongWriter'].each do |atag|
        wfields[atag] = []
        result = row.search("a.#{atag}").map do |href|
          values = to_clean_ascii(href.inner_text, "-").
                gsub(/[\(\)]/, ",").split(/\s*,\s*/)
          wfields[atag].concat(values)
        end.join
      end
      wname     = wfields['SongName']   || []
      wartist   = wfields['Singer']     || []
      wcomposer = wfields['SongWriter'] || []
      href      = row.at("a.SongName")['href']
      p wname, wartist, wcomposer
      if wname.include?(cname)
        if wartist.include?(cartist) || wcomposer.include?(ccomposer)
          return extract_text(track.name, href)
        end
        matchset << [track.name, href]
      end
    end
    if matchset.size > 0
      name, href = matchset.first
      return extract_text(name, href, true)
    end
    sleep(3)
    ""
  end

  def extract_text(title, href, confirm = false)
    repeat = 3
    blocks = []
    pg     = nil
    while repeat > 0
      pg     = fetch_hpricot(href)
      sblock = pg.at("//div#ctl00_Content_pnSong")
      break if sblock
      Plog.warn "Wait for retry - #{repeat}"
      sleep 3
      repeat -= 1
    end
    if repeat <= 0
      Plog.warn "Cannot get lyric block"
      return ""
    end

    blocks = sblock.search("p")
    meta   = blocks[0].inner_text.strip.sub(/:\s*[\r\n]+\s*/, ": ")
    lyric  = blocks[1].inner_html.strip.gsub(/<br ?\/>/, "\n")
    if lyric.empty?
      Plog.warn "No lyrics for #{title}"
      return ""
    end

    wtitle = sblock.at("h1").inner_text
    if !wtitle || wtitle.empty?
      wtitle = title
    end

    if confirm && !confirm_text(lyric)
      return ""
    end

    wtitle + "\n" + meta + "\n\n" + lyric
  end

  def extract_metadata(lyrics)
    if @chset.size > 0
      return @chset
    end
    chset = {}
    cn    = lyrics.split(/[\r\n]+/)
    chset[:name] = cn.shift
    cn.each do |aline|
      puts aline
      if aline =~ /(Composer|Sáng tác|Tác giả):\s*/
        chset[:composer] = $'
      end
    end
    chset
  end
end

class LyNhacTui < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def _auto_get(track)
    cname     = to_clean_ascii(track.name)
    cartist   = to_clean_ascii(track.artist)
    pg        = fetch_hpricot(self.page_url(track.name))
    matchset  = []
    pg.search("div.col-music").each do |row|
      link = row.at("a.ico")
      next unless link
      href = link['href']
      wname, wartist = link['title'].split(/\s*-\s*/)
      wname = to_clean_ascii(wname)
      wartist = wartist ? to_clean_ascii(wartist) : ""
      if wname == cname
        if wartist == cartist
          return extract_text(track.name, href)
        end
        matchset << [track.name, href]
      end
    end
    if true && matchset.size > 0
      name, href = matchset.first
      return extract_text(name, href, true)
    end
    ""
  end

  def extract_text(title, href, confirm = false)
    pg     = fetch_hpricot(@config[:base] + "/#{href}")
    sblock = pg.at("div.content-lyric")
    unless sblock
      Plog.warn "No lyric block"
      return ""
    end
    wtitle = sblock.at("h2.title").inner_text.gsub(/^.*:\s+/, '')
    unless lblock = sblock.at("div#lyric")
      Plog.warn "No lyric block"
      return ""
    end
    lyric  = lblock.inner_html.gsub(/<br +\/?>/, "\n").strip

    if !wtitle || wtitle.empty?
      wtitle = title
    end

    if confirm && !confirm_text(lyric)
      return ""
    end

    wtitle + "\n\n" + lyric
  end

  def extract_metadata(lyrics)
    if @chset.size > 0
      return @chset
    end
    chset = {}
    cn    = lyrics.split(/[\r\n]+/)
    chset[:name] = cn.shift
    cn.each do |aline|
      puts aline
      if aline =~ /(Composer|Sáng tác|Tác giả):\s*/
        chset[:composer] = $'
      end
    end
    chset
  end
end

if (__FILE__ == $0)
  LyricSource.handleCli
end
