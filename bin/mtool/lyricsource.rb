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

    @source   = src || 'console'
    @options  = options
    @config   = DB::Source.find_by_name(src)
    skipfile  = @source + ".yml"
    @chset    = {}
    if false
      @skiplist = HashYaml.new(skipfile)
      at_exit { @skiplist.save }
    else
    end
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
    when :chrome
      unless @chrome
        @chrome = Appscript::app('Google Chrome.app')
        @chrome.activate
        @appref = @chrome.windows.active_tab
      end
      @appref.URL.set url
      counter = 0
      while true
        # Sleep must be first?
        sleep(1)
        if @appref.loading.get.first
          Plog.debug "Document completed."
          # Unfortunately, chrome has no such support.  It's a blind bat now
          content = @appref.source.get.first
          break
        end
        counter += 1
        if (counter >= 10)
          Plog.error "Timeout waiting for #{url}"
          break
        end
      end
    else
      unless @safari
        @safari = Appscript::app('Safari.app')
        @safari.activate
      end
      @safari.document.URL.set url
      counter = 0
      while true
        # Sleep must be first?
        sleep(1)
        pready = @safari.document.do_JavaScript("document.readyState").first
        if pready == "complete"
          Plog.debug "Document completed."
          content = @safari.document.source.get.first
          if content.class == String
            break
          end
        end
        counter += 1
        if (counter >= 10)
          Plog.error "Timeout waiting for #{url}"
          break
        end
      end
    end
    p content.class
    Hpricot(content)
  end

  public
  def page_url(name)
    require 'uri'

    @config[:search_url].gsub(/%TITLE%/, URI.escape(to_clean_ascii(name)))
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
    wset.each do |rec|
      wname, wartist, wcomposer, href = rec
      if wname.is_a?(Array)
        next unless wname.include?(cname)
        if wcomposer.include?(ccomposer) || wartist.include?(cartist)
          return extract_text(track.name, rec, false)
        end
      else
        next unless (wname == cname)
        if (wcomposer == ccomposer) || (wartist == cartist)
          return extract_text(track.name, rec, false)
        end
      end
      mset << [track.name, rec]
    end
    if mset.size > 0
      name, rec = mset.shift
      return extract_text(name, rec, true)
    end
    ""
  end

  def find_match(pg, cname, cartist, ccomposer)
    []
  end

  def extract_metadata(lyrics)
    chset = {}
    cn    = lyrics.split(/[\r\n]+/)
    chset[:name] = cn.shift
    cn.each do |aline|
      if aline =~ /(Composer|Sáng tác|Tác giả|Nhạc Sĩ):\s*/
        chset[:composer] = $'
      end
    end
    chset
  end

  def clean_and_check(lyric, confirm)
    filtered = []
    blcount  = 0
    lyric.split(/(\n|<br \/>)/).each do |l|
      next if l =~ /(yeucahat.com|to your cell|^cf_| LYRICS|<\/span>|<embed>)/i
      next if l == "<br />"
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
    if lyric.empty?
      return nil
    end
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
  
  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    lurl = @config[:base] + "/#{href}"
    Plog.debug("Fetching lyric page ato #{lurl}")
    pg    = fetch_hpricot(lurl)
    title = pg.search("//span.maintitle").inner_text
    if meta  = pg.search("//span.genmed")[1]
      meta = meta.inner_text.strip
    end
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
    unless sblock = pg.search("div.first-search-song")
      return []
    end
    unless link = sblock.search("a._trackLink")[0]
      return []
    end
    wname   = to_clean_ascii(link.inner_text)
    wartist = to_clean_ascii(sblock.search("a.txtBlue")[0].inner_text)
    [[wname, wartist, "", link['href']]]
  end

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    pg    = fetch_hpricot(@config[:base] + "/#{href}")
    lyric = pg.search("p._lyricContent").inner_text.strip
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

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
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

  def find_match(pg, cname, cartist, ccomposer)
    wlinks  = []
    pg.search("li").each do |ele0|
      link = ele0.at('a.link')
      next unless link
      href = link['href']

      wname     = to_clean_ascii(link.inner_text).strip
      auth = ele0.at('a.author')
      wcomposer = to_clean_ascii(auth.inner_text).strip
      next unless link
      wlinks << [wname, "", wcomposer, href]
    end
    wlinks
  end

  def extract_text(title, rec, confirm = false)
    Plog.debug rec.join(" | ")
    wname, wartist, wcomposer, href = rec
    pg    = fetch_hpricot(href)
    lyric = pg.search("td/p[2]").inner_html
    if lyric.empty?
      Plog.debug "No text found in #{href}"
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    "#{title}\nNhạc Sĩ: #{wcomposer}\n\n" + lyric
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

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
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
    title + "\n" + wtitle.strip + "\n" + meta + "\n\n" + lyric
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
    unless block = pg.search("ul.list_song")[0]
      return matchset
    end
    block.children_of_type("li").each do |row|
      link = row.at("h3/a")
      next unless link
      href    = link['href']
      wname   = to_clean_ascii(link.inner_text)
      wartist = row.search("div.info-song//a").map do |lartist|
        to_clean_ascii(lartist.inner_text)
      end
      matchset << [wname, wartist, "", href]
    end
    matchset
  end

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    pg     = fetch_hpricot(@config[:base] + "/#{href}")
    sblock = pg.at("div.lyric")
    unless sblock
      Plog.warn "No lyric block"
      return ""
    end
    wtitle = sblock.at("h2").inner_text.gsub(/^.*:\s+/, '')
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
      if aline =~ /(Composer|Sáng tác|Tác giả|Nhạc Sĩ:):\s*/
        chset[:composer] = $'
      end
    end
    chset
  end
end

if (__FILE__ == $0)
  LyricSource.handleCli
end
