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

require 'hpricot'
module Hpricot
  class Doc
    def text_at(locator, default = "")
      if content = self.at(locator)
        #return content.inner_text.strip
        return content.inner_html.sub(/<.*>/, '').strip
      else
        return default
      end
    end
  end
  class Elem
    def text_at(locator, default = "")
      if content = self.at(locator)
        #return content.inner_text.strip
        return content.inner_html.sub(/<.*>/, '').strip
      else
        return default
      end
    end
  end
end

class LyricSource
  extendCli __FILE__

  LySource = {
    # Javascript protected
    'yeucahat' => {
      :base => "http://search.yeucahat.com",
      :search_url  => "http://search.yeucahat.com/search.php?s=%TITLE%&mode=title"
    },
    'zing' => {
      :base          => "http://mp3.zing.vn",
      :delay_lyfetch => 1,
      :search_url    => "http://mp3.zing.vn/tim-kiem/bai-hat.html?q=%TITLE%"
    },
    # Javascript protected
    'vportal' => {
      :base => "http://vietnameseportal.com/",
      :search_url  => "http://vietnameseportal.com/cgi-bin/lyric/search.cgi?cx=014985440914852074501%3Asliobasbm7a&cof=FORID%3A11&query=%TITLE%&q=%TITLE%"
    },
    # Slow pace - 3-5 secs each
    'tkaraoke' => {
      :base          => "http://lyric.tkaraoke.com",
      :search_url    => "http://lyric.tkaraoke.com/s.tim?q=%TITLE%&t=1",
      :delay_lyfetch => 3,
    },
    'nhactui' => {
      :base => "http://www.nhaccuatui.com",
      :search_url  => "http://www.nhaccuatui.com/tim-kiem?q=%TITLE%"
    },
    'justsome' => {
      :base => "http://www.justsomelyrics.com",
      :search_url  => "http://www.google.com/cse?cx=000975271163936304601%3Ao53s1ouhhyy&q=%TITLE%&sa=Search&cof=FORID%3A0&siteurl=www.justsomelyrics.com%2F#gsc.tab=0&gsc.q=%TITLE%&gsc.page=1",
      :agent => :curl
    },
    # Not yet working
    'video4viet' => {
      :base => "http://www.video4viet.com/lyrics.html",
      :search_url  => "http://www.video4viet.com/lyrics.html?act=search&q=%TITLE%&type=title"
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
    @config   = LySource[src] || {}
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
       gsub(/!/, "").downcase.strip
  end

  def fetch_hpricot(url)
    Plog.info "Fetching #{url}"
    content = ""
    case @config[:agent]
    when :curl
      #Pf.system("open -g '#{url}'", 1)
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
        unless pready = @safari.document.do_JavaScript("document.readyState")
          Plog.info "Waiting for Safari"
          @safari.activate
          next
        end

        if pready.first == "complete"
          Plog.debug "Document completed."
          if delay_lyfetch = @config[:delay_lyfetch]
            sleep(delay_lyfetch)
          end
          content = @safari.document.source.get.first
          if content.class == String
            break
          end
        end
        counter += 1
        if (counter >= 20)
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

    if @config[:search_url]
      @config[:search_url].gsub(/%TITLE%/, URI.escape(to_clean_ascii(name)))
    else
      ""
    end
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
    [result, []]
  end

  def auto_get(track)
    @curtrack = track
    cname     = to_clean_ascii(track.name).sub(/\s*\[.*$/, '')
    cartist   = to_clean_ascii(track.artist).split(/,\s+/)
    ccomposer = to_clean_ascii(track.composer)
    pg        = fetch_hpricot(self.page_url(track.name))

    Plog.debug "Search for #{cname}/#{cartist}/#{ccomposer}"
    wset      = find_match(pg, cname, cartist, ccomposer)
    sleep(3)
    Plog.debug "Found #{wset.size} matching entries"

    # Find another match set?  Is it needed?
    mset = []
    wset.each do |rec|
      wname, wartist, wcomposer, href = rec
      unless wname.is_a?(Array)
        wname = [wname]
      end
      unless wcomposer.is_a?(Array)
        wcomposer = [wcomposer]
      end
      found = false
      wname.each do |awname|
        if to_clean_ascii(awname) == cname
          found = true
          break
        end
      end
      next unless found
      found = false
      wcomposer.each do |awcomposer|
        if to_clean_ascii(awcomposer) == ccomposer
          found = true
          break
        end
      end
      if found || ((wartist & cartist).size <= 0)
        mset << [track.name, rec, false]
        next
      end
      mset << [track.name, rec, true]
    end
    mset = mset[0..9]
    Plog.info "Filter to #{mset.size} matching entries"

    # Extract the 1st one with data
    mset.each do |name, rec, xtype|
      result, meta = extract_text(name, rec, xtype)
      unless result.empty?
        output = {
          :name     => rec[0],
          :artist   => rec[1],
          :composer => rec[2],
          :url      => rec[3],
          :content  => result
        }
        # Page parsing may also add more meta data
        if meta
          output.update(meta)
        end
        return output
      end
    end
    return nil
  end

  def find_match(pg, cname, cartist, ccomposer)
    []
  end

  def clean_and_check(lyric, to_confirm)
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
    if to_confirm
      @curtrack.play
      puts @curtrack.name + "\n==========\n"
      puts lyric.gsub(/\n+/, "\n")
      unless Cli.confirm("OK to save this")
        return nil
      end
    end
    lyric
  end
end

class LyVideo4Viet < LyricSource
  def find_match(pg, cname, cartist, ccomposer)
    result = []
    pg.search("td.lyricrow/a").each_slice(2).each do |wname, wcomposer|
      href      = wname['href']
      wname     = to_clean_ascii(wname.inner_text)
      wcomposer = to_clean_ascii(wcomposer.inner_text)
      wartist   = ""
      result << [wname, [wartist], [wcomposer], href]
    end
    result
  end

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    lurl = @config[:base] + "#{href}"
    Plog.debug("Fetching lyric page at #{lurl}")

    pg    = fetch_hpricot(lurl)
    unless content = pg.at("div.content/center")
      return ""
    end
    lyric = content.inner_html.gsub(/<br\s*\/>/, "\n").
        gsub(/<[^>]+>/, '')
    if lyric.empty?
      return ""
    end
    meta = {}
    meta[:name]     = pg.text_at("div.content/center/h3")
    meta[:composer] = pg.text_at("div.content/center//strong").sub(/^.*:\s+/, '')
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    [lyric, meta]
  end
end

class LyYeuCaHat < LyricSource
  def find_match(pg, cname, cartist, ccomposer)
    unless tb0 = pg.at("//table.forumline")
      Plog.error "No keyblock found in page"
      return []
    end
    match_info = []
    
    (tb0.search("//tr.row1") + tb0.search("//tr.row2")).each do |arow|
      aref      = arow.at("//a.topictitle")
      href      = aref['href']
      wname     = to_clean_ascii(aref.inner_text)
      wartist   = to_clean_ascii(File.basename(href).sub(/^.*~/, '').
              sub(/\.html$/, '').gsub(/-/, ' '))
      cref      = arow.search("//span.gensmall")[1]
      wcomposer = to_clean_ascii(cref.children[3].to_s)
      if (ccomposer =~ /#{wcomposer}/) || (cartist =~ /#{wartist}/)
        return [[wname, [wartist], [wcomposer], href]]
      end
      match_info << [wname, [wartist], [wcomposer], href]
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
    lyric = pg.text_at("//span.lyric")
    if lyric.empty?
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    [title + "\n" + meta + "\n" + lyric, {}]
  end
end

class LyZing < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def find_match(pg, cname, cartist, ccomposer)
    result    = []
    other_res = []
    ["div.first-search-song", "div.content-item.ie-fix"].each do |div_ident|
       pg.search(div_ident).each do |adiv|
          if link = adiv.at("a._trackLink")
            wname   = to_clean_ascii(link.inner_text)
            #p link, wname, cname
            break unless wname == cname
            wartist = to_clean_ascii(adiv.text_at("a.txtBlue"))
            if cartist.include?(wartist)
              result << [wname, [wartist], [""], link['href']]
            else
              other_res << [wname, [wartist], [""], link['href']]
            end
          else
            Plog.warn "No link found for #{adiv}"
          end
       end
    end
    if result.size > 0
      result
    else
      other_res
    end
  end

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    pg    = fetch_hpricot(@config[:base] + "/#{href}")
    lyric = pg.text_at("p._lyricContent")
    meta = {}
    if txtBlue = pg.text_at("a.txtBlue", nil)
      meta[:composer] = txtBlue
    end
    if lyric.empty?
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end

    meta[:composer] = pg.text_at("p.song-info//a.txtBlue")
    meta[:name]     = pg.text_at("h3/strong")

    ["#{title}\nSang tac: #{meta[:composer]}\n#{lyric}\n#{href}", meta]
  end
end

class LyJustSome < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def find_match(pg, cname, cartist, ccomposer)
    wlinks_all      = []
    wlinks_w_artist = []
    pg.search("//div//a").each do |ele|
      href      = ele['href']
      bname     = URI.unescape(File.basename(href))
      checklink = bname.sub(/-lyrics$/i, '').vnto_ascii.downcase.gsub(/-/, ' ')
      if (checklink =~ /#{cname}/)
        cartist.each do |cartist0|
          if (checklink =~ /#{cartist0}/)
            wlinks_w_artist << [cname, [cartist0], [""], href]
            break
          end
        end
        wlinks_all << [cname, [""], [""], href]
      end
    end
    if wlinks_w_artist.size > 0
      return wlinks_w_artist
    else
      return wlinks_all
    end
  end

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    pg    = fetch_hpricot(href)
    lyric = pg.text_at("div#content")
    if lyric.empty?
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ""
    end
    [title + "\n" + lyric, {}]
  end
end

class LyVPortal < LyricSource

  def find_match(pg, cname, cartist, ccomposer)
    wlinks  = []
    pg.search("li").each do |ele0|
      link = ele0.at('a.link')
      next unless link
      href = link['href']

      wname = to_clean_ascii(link.inner_text).strip
      auth  = ele0.text_at('a.author')
      wcomposer = to_clean_ascii(auth)
      next unless link
      wlinks << [wname, [""], [wcomposer], href]
    end
    wlinks
  end

  def extract_text(title, rec, confirm = false)
    wname, wartist, wcomposer, href = rec
    pg       = fetch_hpricot(href)
    lyric    = pg.search("td/p").inner_html
    composer = pg.text_at("a.sub_cat")
    if lyric.empty?
      Plog.debug "No text found in #{href}"
      return ""
    end
    unless lyric = clean_and_check(lyric, confirm)
      return ["", {}]
    end
    ["#{title}\nNhac Si: #{composer}\n\n" + lyric, {}]
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
          values = href.inner_text.gsub(/[\(\)]/, ",").split(/\s*,\s*/)
          #if atag != "SongName"
            #values = values.map{|f| to_clean_ascii(f, "-")}
          #end
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
    [title + "\n" + wtitle.strip + "\n" + meta + "\n\n" + lyric, {}]
  end
end

class LyNhacTui < LyricSource
  # Get and parse automatically
  # @param [ITuneTrack] track
  def old_find_match(pg, cname, cartist, ccomposer)
    matchset  = []
    unless block = pg.at("ul.list_song")
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
      next unless ((cartist & wartist).size > 0)
      matchset << [wname, wartist, "", href]
    end
    matchset
  end

  def find_match(pg, cname, cartist, ccomposer)
    matchset  = []
    unless block = pg.at("div.new-song.song-home")
      return matchset
    end
    block.search("li.clearfix.song-item").each do |row|
      link = row.at("span.rel/a")
      next unless link
      href    = link['href']
      wname   = to_clean_ascii(link.inner_text)
      wartist = to_clean_ascii(row.search("div.singer").inner_text)
      next if (wname == "") && (wartist == "")
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
    [wtitle + "\n\n" + lyric, {}]
  end
end

if (__FILE__ == $0)
  LyricSource.handleCli
end
