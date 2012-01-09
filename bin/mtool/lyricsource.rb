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
      :src  => "http://www.google.com/cse?cx=000975271163936304601%3Ao53s1ouhhyy&q=%TITLE%&sa=Search&cof=FORID%3A0&siteurl=www.justsomelyrics.com%2F#gsc.tab=0&gsc.q=%TITLE%&gsc.page=1",
      :agent => :curl
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
      :base => "http://vietnameseportal.com/",
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
    require 'appscript'

    @source  = src || 'console'
    @options = options
    @config  = LySource[src]

    skipfile  = @source + ".yml"
    @skiplist = HashYaml.new(skipfile)
    @chset    = {}
    @safari   = Appscript::app('Safari.app')
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
    content = ""
    case @config[:agent]
    when :curl
      Pf.system("open -g '#{url}'", 1)
      content = `curl --silent -A Mozilla/4.0 "#{url}"`
    else
      @safari.activate
      @safari.document.URL.set url
      counter = 0
      while true
        # Sleep must be first?
        sleep(1)
        pready = @safari.document.do_JavaScript("document.readyState").first
        if pready == "complete"
          Plog.debug "Document completed."
          content = @safari.document.source.get.first
          break
        end
        counter += 1
        if (counter >= 10)
          Plog.error "Timeout waiting for #{url}"
          break
        end
      end
    end
    Hpricot(content)
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
    cname     = to_clean_ascii(track.name)
    cartist   = to_clean_ascii(track.artist)
    ccomposer = to_clean_ascii(track.composer)
    pg        = fetch_hpricot(self.page_url(track.name))
    wset      = find_match(pg, cname, cartist, ccomposer)

    mset = []
    wset.each do |wname, wartist, wcomposer, href|
      if wname.is_a?(Array)
        next unless wname.include?(cname)
        if wcomposer.include?(ccomposer) || wartist.include?(cartist)
          return extract_text(track.name, href, false)
        end
      else
        next unless (wname == cname)
        if (wcomposer == ccomposer) || (wartist == cartist)
          return extract_text(track.name, href, false)
        end
      end
      mset << [track.name, href]
    end
    if mset.size > 0
      name, href = mset.shift
      return extract_text(name, href, true)
    end
    ""
  end

  def find_match(pg, cname, cartist, ccomposer)
    []
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

  def clean_and_check(lyric, confirm)
    filtered = []
    blcount  = 0
    lyric.split(/\n/).each do |l|
      next if l =~ /(yeucahat.com|to your cell|^cf_| LYRICS)/i
      l = l.strip
      if l.empty?
        blcount += 1
        next if (blcount >= 2)
      else
        blcount = 0
      end
      filtered << l
    end
    lyric = filtered.join("\n")
    if confirm
      @curtrack.play
      puts @curtrack.name + "\n==========\n"
      puts lyric
      unless Cli.confirm("OK to save this")
        return nil
      end
    end
    lyric
  end
end

class LyVideo4Viet < LyricSource
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
  def find_match(pg, cname, cartist, ccomposer)
    tb0        = pg.at("//table.forumline")
    match_info = []
    (tb0.search("//tr.row1") + tb0.search("//tr.row2")).each do |arow|
      aref      = arow.at("//a.topictitle")
      href      = aref['href']
      wname     = to_clean_ascii(aref.inner_text)
      wartist   = to_clean_ascii(File.basename(href).sub(/^.*~/, '').
              sub(/\.html$/, '').gsub(/-/, ' '))
      cref      = arow.search("//span.gensmall")[1]
      wcomposer = to_clean_ascii(cref.children[3].to_s)
      match_info << [wname, wartist, wcomposer, href]
    end
    match_info
  end
  
  def extract_text(title, href, confirm = false)
    lurl = @config[:base] + "/#{href}"
    Plog.debug("Fetching lyric page ato #{lurl}")
    pg    = fetch_hpricot(lurl)
    title = pg.search("//span.maintitle").inner_text
    meta  = pg.search("//span.genmed")[1].inner_text.strip
    lyric = pg.search("//span.lyric").inner_text.strip
    if lyric.empty?
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    title + "\n" + meta + "\n" + lyric
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
  def find_match(pg, cname, cartist, ccomposer)
    wset    = []
    pg.search("div.content-item/h3").each do |ele0|
      ele      = ele0.at('a')
      haslyric = ele0.at('img.hlyric')
      next unless haslyric

      title, wartist = ele['title'].split(/\s*-\s*/)
      wname   = to_clean_ascii(title)
      wartist = to_clean_ascii(wartist)
      wset << [wname, wartist, "", ele['href']]
    end
    wset
  end

  def extract_text(title, href, confirm = false)
    pg    = fetch_hpricot(@config[:base] + "/#{href}")
    lyric = pg.search("//p._lyricContent").inner_text.strip
    if lyric.empty?
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
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
  def find_match(pg, cname, cartist, ccomposer)
    wlinks  = []
    pg.search("//div//a").each do |ele|
      href      = ele['href']
      bname     = URI.unescape(File.basename(href))
      checklink = bname.sub(/-lyrics$/i, '').vnto_ascii.downcase.gsub(/-/, ' ')
      if (checklink =~ /#{cname}/)
        if (checklink =~ /#{cartist}/)
          wlinks << [cname, cartist, "", href]
        else
          wlinks << [cname, "", "", href]
        end
      end
    end
    wlinks
  end

  def extract_text(title, href, confirm = false)
    pg    = fetch_hpricot(href)
    lyric = pg.search("//center").inner_text.strip
    if lyric.empty?
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    title + "\n" + lyric
  end

  def extract_metadata(lyrics)
    chset = {}
    cn    = lyrics.split(/[\r\n]+/)
    cn.each do |aline|
      puts aline
      if aline =~ /(Composer|Sáng tác):\s*/
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
  def find_match(pg, cname, cartist, ccomposer)
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
      Plog.debug "wname: #{wname}, #{wartist}, #{wcomposer}"
      matchset << [wname, wartist, wcomposer, href]
    end
    matchset
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
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    # User must edit to select a good one.  I dont know which is good
    title + "\n" + wtitle + "\n" + meta + "\n\n" + lyric
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
  def find_match(pg, cname, cartist, ccomposer)
    matchset  = []
    pg.search("div.col-music").each do |row|
      link = row.at("a.ico")
      next unless link
      href = link['href']
      wname, wartist = link['title'].split(/\s*-\s*/)
      wname = to_clean_ascii(wname)
      wartist = wartist ? to_clean_ascii(wartist) : ""
      matchset << [wname, wartist, "", href]
    end
    matchset
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
    unless lyric = clean_and_check(lyric, confirm)
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
