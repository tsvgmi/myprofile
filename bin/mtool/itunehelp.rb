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
require 'mtool/mp3file'

class HashYaml
  def initialize(yfile)
    @yfile = yfile
    if test(?f, yfile)
      @content = YAML.load_file(yfile)
    else
      @content = {}
    end
  end

  def save
    if test(?f, @yfile)
      FileUtils.move(@yfile, "#{@yfile}.bak", :force=>true, :verbose=>true)
    end
    fod = File.open(@yfile, "w")
    fod.puts(@content.to_yaml)
    fod.close
  end

  def method_missing(meth, *args)
    @content.send(meth, *args)
  end
end

class PhotoInfo
  def initialize
    require 'find'

    @images = []
    Find.find("#{ENV['HOME']}/itune-dump/images") do |afile|
      if afile =~ /\.jpg$/
        @images << afile
      end
    end
  end

  def mk_thumbnail(ofile, size)
    rndfile = @images[rand(@images.size)]
    if rndfile
      Pf.system("convert '#{rndfile}' -adaptive-resize #{size} '#{ofile}'", 1)
      test(?f, ofile)
    else
      EmLog.error("No stock image file found")
      false
    end
  end
end

# Mapping of Viet UTF-8 string to ASCII
class VnMap
  require 'utfstring'

  @@fmap, @@rmap = nil, nil

  def self.load_map(mfile)
    @@fmap = YAML.load_file(mfile)
    @@rmap = {}
    @@fmap.each do |mc, mapset|
      mapset.each do |seq|
        @@rmap[seq] = mc
      end
    end
  end

  def self.to_ascii(string)
    unless @@rmap
      load_map("#{ENV['EM_HOME_DIR']}/etc/vnmap.yml")
    end
    result = ""
    string.each_utf8_char do |achar|
      if mchar = @@rmap[achar]
        result << mchar
      elsif achar =~ /^[\w\s]+$/
        result << achar
      end
    end
    result
  end
end

module ITune
  class ITuneApp
    @@app = nil

    def self.app
      require 'appscript'

      unless @@app
        Plog.info "Connect to iTunes"
        @@app = Appscript::app('iTunes')
        #@@app.activate
      end
      @@app
    end
  end

  class DeviceDir
    attr_reader :dir, :full, :tracks, :wlist

    def initialize(devspec, options={})
      @app        = ITuneApp.app
      @options    = options
      @dir, dsize = devspec.split(/:/)
      @maxsize    = dsize ? dsize.to_i*10 : 1_000_000_000
      @cursize    = 0
      @tracks     = []
      @full       = false
      @wlist      = []
    end

    def try_add(atrack)
      file  = atrack.location.to_s
      album = atrack.album.gsub(/\//, '_')
      dfile = "#{@dir}/#{album}/#{File.basename(file)}"
       
      # File is not accessible ?
      unless test(?f, file)
        Plog.error "#{file} not accessible"
        return false
      end

      fsize   = (File.size(file)+99999)/100000
      newsize = @cursize + fsize
      if newsize > @maxsize
        @full = true
        false
      else
        @cursize = newsize
        @tracks << atrack
        @wlist << [file, dfile, album]
      end
    end

    # Put a thumbnail on each dir
    def add_images
      require 'find'

      size      = @options[:size] || "100x100"
      cache_dir = @options[:cdir] || "./images"
      cvname    = @options[:dvname] || "cover.jpg"
      verbose   = @options[:verbose]
      
      unless test(?d, cache_dir)
        FileUtil.mkpath(cache_dir, :verbose=>verbose)
      end
      dircount  = {}

      photoinfo = PhotoInfo.new
      `find #{@dir}`.split("\n").each do |afile|

        next if afile =~ /.(bmp|jpg)$/o
        next if afile =~ /#{@dir}$/o

        if test(?d, afile)
          dircount[afile] ||= 0
          dircount[afile] += 1
          next
        end

        wdir = File.dirname(afile)
        dircount[wdir] ||= 0
        dircount[wdir] += 1
        album  = File.split(wdir).last.gsub(/\'/, '')
        cvfile = "#{wdir}/#{cvname}"

        unless test(?f, cvfile)
          m3info = Mp3Shell.new(afile, @options)
          cafile = "#{cache_dir}/#{album}-#{size}.jpg"
          cache  = true
          unless test(?f, cafile)
            unless m3info.mk_thumbnail(cafile, size)
              unless photoinfo.mk_thumbnail(cafile, size)
                next
              end
              cache = false
            end
          end
          if test(?f, cafile)
            FileUtils.cp(cafile, cvfile, :verbose=>verbose)
            unless cache
              FileUtils.remove(cafile, :verbose=>verbose)
            end
          else
            Plog.error "#{cafile} not created?"
          end
        end
      end

      # Dir count contain count of non-image files
      dircount.keys.sort.each do |k|
        v = dircount[k]
        next if k == dir
        if v <= 1
          FileUtils.rm_rf(k, :verbose=>true)
        end
      end
      true
    end

    def copyfiles(content)
      cfiles = []
      fcount = content.size
      counter = 0
      content.each do |sfile, dfile|
        counter += 1
        if test(?f, dfile)
          Plog.info "Destination #{dfile} exists - skip"
          next
        end
        if !test(?f, sfile)
          Plog.info "Source #{sfile} does not exist - skip"
          next
        end
        ddir = File.dirname(dfile)
        unless test(?d, ddir)
          FileUtils.mkpath(ddir, :verbose=>@options[:verbose])
        end
        Plog.info "#{counter}/#{fcount} - #{sfile}"
        FileUtils.cp(sfile, dfile)
        cfiles << dfile
      end
      cfiles
    end

    def rm_empty_dirs
      require 'find'

      protect = false
      Find.find(@dir) do |afile|
        next unless test(?f, afile)
        if afile !~ /\.(ini|jpg|DS_Store)$/
          protect = true
          puts "#{afile} should be protected from #{@dir}"
          break
        end
      end
      unless protect
        FileUtils.rm_rf(@dir, :verbose=>true)
      end
    end
  end

# Manage iTune tracks and update access via iTune app interface
  class ITuneTrack
    attr_accessor :track

    def initialize(track)
      @track = track
      @kname = nil
    end

    def name_clean
      unless @kname
        name   = @track.name.get
        @kname = VnMap.to_ascii(name).sub(/\s*[-\(].*$/, '').strip
      end
      @kname
    end

    def updates(props, options = {})
      changed = false
      props.each do |prop, newval|
        curval = @track.send(prop).get
        curval = self[prop]
        if curval == newval
          changed = true
          next
        end
        unless changed
          puts "N: #{@track.name.get}/#{@track.album.get}"
        end
        changed = true
        puts "  %-10s: %-30s => %-30s" % [prop, curval, newval]
        unless ITuneHelper.getOption(:dryrun)
          begin
            @track.send(prop).set(newval.strip)
          rescue => errmsg
            p errmsg
          end
        end
      end
      changed
    end

    def show
      composer = @track.composer.get
      artist   = @track.artist.get
      comp     = @track.compilation.get
      Plog.info "N:#{name_clean}, C:#{composer}, A:#{artist}, CO:#{comp}"
    end

    def [](property)
      result = @track.send(property).get
      if result == :missing_value
        result = ""
      end
      result
    end

    def []=(property, value)
      @track.send(property).set(value.strip)
    end

    def method_missing(method, *args)
      case method
      when :reveal, :play
        begin
          @track.send(method, *args)
        rescue Appscript::CommandError => errmsg
          p errmsg
        end
      else
        if (method.to_s =~ /=$/)
          @track.send($`).set(*args)
        elsif (args.size == 0)
          @track.send(method).get
        else
          @track.send(method, *args)
        end
      end
    end
  end

  class LyricSource
    LySource = {
      'video4viet' => {
        :base => "http://www.video4viet.com",
        :src  => "http://www.video4viet.com/lyrics.html?act=search&q=%TITLE%&type=title"
      },
      'yeucahat' => {
        :base => "http://search.yeucahat.com",
        :src  => "http://search.yeucahat.com/search.php?s=%TITLE%&mode=title"
      }
    }

    def initialize(src)
      @source = src
      @config = LySource[src]
      raise "Lyrics source #{@source} not found" unless @config
    end

    private
    def to_clean_ascii(string)
      VnMap.to_ascii(string).sub(/\s*[\-\(].*$/, '').
                         gsub(/\'/, " ").downcase
    end

    public
    def page_url(name)
      require 'uri'

      @config[:src].sub(/%TITLE%/, URI.escape(to_clean_ascii(name)))
    end

    # Get and parse manually
    # @param [ITuneTrack] track
    def manual_get(track)
      Pf.system("open --background '#{self.page_url(track.name)}'", 1)
      STDOUT.puts "Enter content for lyrics [ = to end]: "
      content = []
      while line = STDIN.gets.chomp
        break if line =~ /^=/
        content << line
      end
      result = content.join("\n").strip
    end

    def extract_from_yeucahat(href)
      require 'hpricot'
      require 'open-uri'

      wurl  = @config[:base] + "/#{href}"
      Plog.info "Found match in #{wurl}"
      fid   = open(wurl)
      pg    = Hpricot(fid.read)
      fid.close
      title = pg.search("//span.maintitle").inner_text
      meta  = pg.search("//span.genmed")[1].inner_text.strip
      lyric = pg.search("//span.lyric").inner_text.strip
      if title.empty?
        ""
      else
        title + "\n" + meta + "\n" + lyric + "\n" + wurl
      end
    end

    # Get and parse automatically
    # @param [ITuneTrack] track
    def auto_get(track)
      require 'hpricot'
      require 'open-uri'

      case @source
      when "yeucahat"
        url = self.page_url(track.name)
        Plog.info "Fetching from #{url}"
        fid = open(url)
        pg  = Hpricot(fid.read)
        fid.close

        cname   = to_clean_ascii(track.name)
        cartist = to_clean_ascii(track.artist)
        if true
          tb0 = pg.search("//table.forumline")[0]
          (tb0.search("//tr.row1") + tb0.search("//tr.row2")).each do |arow|
            aref  = arow.at("//a.topictitle")
            href  = aref['href']
            wname = to_clean_ascii(aref.inner_text)
            next unless (wname == cname)
            wartist = to_clean_ascii(File.basename(href).sub(/^.*~/, '').
                    sub(/\.html$/, '').gsub(/-/, ' '))
            if (wartist == cartist)
              return extract_from_yeucahat(href)
            else
              ccomposer = to_clean_ascii(track.composer)
              cref      = arow.search("//span.gensmall")[1]
              wcomposer = to_clean_ascii(cref.children[3])
              Plog.info "Found composer #{wcomposer}"
              if (wcomposer == ccomposer)
                return extract_from_yeucahat(href)
              end
            end
          end
        else
          pg.search("//a.topictitle").each do |aref|
            href    = aref['href']
            wname   = to_clean_ascii(aref.inner_text)
            wartist = to_clean_ascii(File.basename(href).sub(/^.*~/, '').
                    sub(/\.html$/, '').gsub(/-/, ' '))
            if (wname == cname) && (wartist == cartist)
              wurl = @config[:base] + "/#{href}"
              Plog.info "Found match in #{wurl}"
              fid = open(wurl)
              pg  = Hpricot(fid.read)
              fid.close
              title = pg.search("//span.maintitle").inner_text
              meta  = pg.search("//span.genmed")[1].inner_text.strip
              lyric = pg.search("//span.lyric").inner_text.strip
              unless title.empty?
                return title + "\n" + meta + "\n" + lyric + "\n" + wurl
              end
            end
          end
        end
      end
      ""
    end

    def sync_meta_to_itune(lyrics)
      cn    = lyrics.split(/[\r\n]+/)
      chset = {}
      title = cn[0].strip
      case @source
      when 'video4viet'
        if (cn[1] =~ /:\s*/)
          chset[:name]     = title unless title.empty?
          chset[:composer] = $'.sub(/\s*[-\(;].*$/, '')
        else
          Plog.error "#{@kname}. Lyrics not in valid form"
        end
      when 'yeucahat'
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
      end
      chset
    end
  end

# Manage the external lyric store.  This is kept outside and clone
# into the tracks, b/c many tracks are of the same song, and it is
# too time consuming to get for each one.
  class LyricStore
    MIN_SIZE = 100

    # @param [String]     store Directory to store
    # @param [ITuneTrack] track iTune track
    def initialize(src, store, track)
      @store = store
      unless test(?d, store)
        FileUtils.mkdir_p(store, :verbose=>true)
      end
      @track = track

      name      = @track.name
      @kname    = VnMap.to_ascii(name).sub(/\s*[-\(].*$/, '').strip
      @source   = src
      @lysource = LyricSource.new(src)
    end

# @return [String] Content of lyric in store.  Text format
    def value
      wfile    = "#{@store}/#{@kname}.2txt"
      if test(?f, wfile)
        YAML.load_file(wfile)[:content]
      else
        wfile  = "#{@store}/#{@kname}.txt"
        if test(?f, wfile)
          File.read wfile
        else
          ""
        end
      end
    end

# @param [String] content Content to set to lyric text in store
    def value=(content)
      wfile    = "#{@store}/#{@kname}.2txt"
      if content
        Plog.info "Writing to #{wfile}"
        fod = File.open(wfile, "w")
        fod.puts({
          :source  => @source,
          :content => content
        }.to_yaml)
        fod.close
      else
        if test(?f, wfile)
          FileUtils.remove(wfile, :verbose=>true)
        end
      end
    end

# Check the store and set to the track if needed
# @param [Boolean] force Force overwrite of track data
    def store_to_track(force = false)
      clyrics = self.value
      if clyrics.size >= MIN_SIZE
        unless force
          tlyrics = @track.lyrics
          if tlyrics.size >= MIN_SIZE
            return true
          end
        end
        chset = @lysource.sync_meta_to_itune(clyrics)
        if chset.size > 0
          Plog.info "Setting lyric for #{@kname}"
          @track.updates(chset)
        end
        @track.lyrics  = clyrics
        @track.comment = Time.now.strftime("%y.%m.%d.%H.%M.%S")
        return true
      else
        clyrics = @track[:lyrics]
        if clyrics.size >= MIN_SIZE
          self.value = clyrics
          return true
        end
      end
      Plog.error "#{@kname}. No setting to lyrics"
      false
    end

    # Remove the track info from both the current track and local store
    def clear_track
      Plog.info "#{@kname}. Clearing lyrics"
      @track.lyrics  = ""
      @track.comment = ""
      self.value = nil
      return true
    end

    # Set the lyrics content from web or store.
    #
    # If lyrics is not found in local store, we'll point to remote URL
    # so user could get/cut/paste to local store.  If auto is set,
    # this will check both title/artist and if found on remote, will
    # automatically retrieve, save to local store and track
    #
    # @param [Boolean] auto Auto extract and
    def set_track_lyric(auto)
      skipfile = @source + ".yml"
      skiplist = HashYaml.new(skipfile)
      name     = @kname
      return if skiplist[name]
      return if store_to_track

      composer = @track.composer
      lyrics   = @track[:lyrics]
      album    = @track.album
      Plog.info "N: #{name}/#{album}, C: #{composer}"
      changed  = false
      if lyrics.empty? || (lyrics.size < MIN_SIZE)
        @track.reveal
        if auto
          content = @lysource.auto_get(@track)
        else
          @track.play
          content = @lysource.manual_get(@track.name)
        end
        if content.empty?
          skiplist[name] = true
          skiplist.save
        else
          Plog.info "Set webcontent to #{@track.name_clean}"
          self.value = content
          changed = store_to_track
        end
      end
      # Do it inside the look cause we use 'ctrl-c' to break out
      true
    end

    def self.build_index(dir = ".")
      index = HashYaml.new("#{dir}/index.yml")
      Dir.glob("#{dir}/*.txt").each do |afile|
        fname = File.basename(afile).sub(/\.txt$/, '')
        next if index[fname]
        line2 = File.read(afile).split(/[\r\n]+/)[1]
        next unless (line2 =~ /:/)
        artist = $'.strip
        index[fname] = {
          :file       => afile,
          :artist     => VnMap.to_ascii(artist).sub(/\s*\(.*$/, ''),
          :raw_artist => artist
        }
      end
      index.save
    end
  end

  class ITuneFolder
    attr_reader :tracks

    def initialize(name, options={})
      @name    = name
      @app     = ITuneApp.app
      @ifolder = nil
      @options = options
      @tracks  = []
      case @name
      when "current"
        @ifolder = @app.browser_windows[1].view
      when "select"
        @ifolder = @app.selection
      else
        if sources = @app.sources[1]
          if wset = sources.playlists.name.get.zip(
            sources.playlists.get).find {|lname, list|
              lname == name}
            @ifolder = wset[1]
          end
        end
      end
      unless @ifolder
        raise "Folder #{name} not found"
      end
      Plog.info "Using folder #{@name}"
      get_tracks(@options[:pattern])
    end

    def get_tracks(ptn = nil)
      if ptn
        Plog.info "Search for #{ptn}"
        @tracks = @ifolder.search :for=>ptn.gsub(/\./, ' ')
      elsif @name == "select"
        @tracks = @ifolder.get
      else
        @tracks = @ifolder.tracks.get
      end
      @tracks
    end

    def filter_list
      limit = (@options[:limit] || 100000).to_i
      @tracks.each do |atrack|
        atrack2  = ITuneTrack.new(atrack)
        if yield atrack2, atrack2.name_clean.downcase
          limit -= 1
        end
        if @options[:verbose]
          STDERR.print('.'); STDERR.flush
        end
        break if (limit <= 0)
      end
      STDERR.puts if @options[:verbose]
    end

    # Clone and extract composer field
    def clone_composer(dbfile)
      wset = HashYaml.new(dbfile)
      self.filter_list do |atrack, iname|
        composer = atrack.composer
        changed  = false
        if composer.empty?
          if wset[iname] && (wset[iname].size > 0)
            changed |= atrack.updates(:composer => wset[iname].first)
          end
        else
          wset[iname] ||= VnMap.to_ascii(composer)
        end
        changed
      end
      wset.save
    end

    def capitalize(string)
      result = if string =~ /\s*\((.*)\)(.*)$/
        p1, p2, p3 = $`, $1, $2
        capitalize(p1) + ' (' + capitalize(p2) + ') ' + capitalize(p3)
      else
        string.split(/[ _]+/).map {|w| w.capitalize}.join(' ')
      end
      result.strip
    end

    SpecialName = {
      'Abba'  => 'ABBA',
      'Ac, M' => 'AC&M',
      'Maya'  => 'MayA'
    }

    def find_match
      mainFolder = ITuneFolder.new('Music')
      self.filter_list do |atrack, iname|
        atrack.show
        pattern = "#{atrack.name} #{atrack.artist}"
        mainFolder.get_tracks(pattern)
        mainFolder.filter_list do |mtrack, mname|
          mtrack.show
        end
      end
      true
    end

    def sub_artist(subfile)
      subdefs = YAML.load_file(subfile)
      self.filter_list do |atrack, iname|
        updset = {}
        ['artist', 'album_artist'].each do |prop|
          value  = atrack[prop]
          nvalue = value.split(/\s*,\s*/).sort.map do |avalue|
            subdefs.each do |k, v|
              avalue = avalue.sub(/#{k}/i, v)
            end
            avalue
          end.join(', ')
          updset[prop] = nvalue
        end
        atrack.updates(updset)
      end
      true
    end

    def stats(dbfile)
      counters = Hash.new(0)
      self.filter_list do |atrack, iname|
        if !atrack.composer.empty?
          counters['has_composer'] += 1
        end
        [:artist, :composer, :album_artist].each do |f|
          v = VnMap.to_ascii(atrack[f])
          if !v.empty?
            cname = "#{f}_#{v.gsub(/[ ,\/]+/, '_')}"
            counters[cname] += 1
          end
        end
      end
      fod = File.open(dbfile, "w")
      fod.puts counters.to_yaml
      fod.close
      true
    end

    def update_if_changed(dir)
      index = HashYaml.new("#{dir}/index.yml")
      self.filter_list do |atrack, iname|
        tname   = VnMap.to_ascii(atrack.name).sub(/\s*\(.*$/, '')
        identry = index[tname]
        next unless identry

        comment = atrack.comment
        tset    = comment.split(/\./)
        updtime = Time.at(0)
        if tset.size >= 6
          begin
            updtime = Time.local(*tset)
          rescue
          end
        end
        file = identry[:file]
        if @options[:force] || (updtime < File.mtime(file))
          Plog.info "Updating #{tname} from #{file}"
          LyricStore.new("video4viet", dir, atrack).store_to_track(true)
        end
      end
    end

    def track_run(instruction)
      ntracks  = @options[:tracks] || @tracks.size
      curtrack = 0
      updopts  = {
        :overwrite => @options[:overwrite]
      }
      self.filter_list do |atrack, iname|
        name    = atrack.name
        case instruction
        # Track in the form: title(composer)
        when 'e.composer'
          composer = nil
          if name =~ /^(.*)\s*\((.*)\)/
            tname, composer = $1, $2
          elsif name =~ /^(.*)\s*-\s*(.*)$/
            tname, composer = $1, $2
          end
          updset = {}
          if composer
            if atrack.composer.empty?
              updset[:composer] = composer
            end
            updset[:name] = tname
          end
          atrack.updates(updset)
        when 'flip.name.artist'
          name   = atrack.name
          artist = atrack.artist
          next unless name
          atrack.updates(:name => artist, :artist => name)
        when 'b.artist'
          artist, title = atrack.name.split(/\s*-\s*/)
          next unless title
          atrack.updates(:name => title, :artist => artist)
        when 'a.artist'
          title, artist = atrack.name.split(/\s*-\s*/)
          next unless artist
          atrack.updates(:name => title, :artist => artist)
        # Capitalize name
        when 'cap'
          updset = {}
          ['name', 'artist', 'album_artist'].each do |prop|
            value  = atrack[prop]
            nvalue = capitalize(value)
            unless SpecialName[nvalue]
              updset[prop] = nvalue
            end
          end
          atrack.updates(updset)
        # To undo changes to artist name with special spelling
        when 'fix_artist'
          updset = {}
          ['artist', 'album_artist'].each do |prop|
            value = atrack[prop]
            if nvalue = SpecialName[value]
              updset[prop] = nvalue
            end
          end
          atrack.updates(updset)
        # General fix
        # Update Lien Khuc to LK
        # Remove all after -
        when 'clean_name'
          fixname = atrack.name.sub(/^Lien Khuc/i, 'LK').
                  sub(/^:/, '').
                  sub(/\s*-.*$/, '')
          if fixname =~ /^(.*)\s*\(.*$/
            fixname = $1
          end
          atrack.updates(:name => fixname)

        # Remove the track info in front of name and move to track
        when 'number_track'
          updset = {}
          if name =~ /^(\d+)[-\.]?\s*/
            trackno = $1.to_i
            rname   = $'
            updset[:track_number] = trackno
            updset[:name]         = rname
          elsif name =~ /^\s*-\s*/
            updset[:name]         = $'
          end
          atrack.updates(updset)
        when 'renumber_track'
          curtrack += 1
          atrack.updates({:track_number => curtrack,
                          :track_count => ntracks}, updopts)
        when 'show'
          atrack.show
        when 'setcomp'
          atrack.updates(:compilation => true)
        when 'clearcomp'
          atrack.updates(:compilation => false)
        # Resplit the artist field
        when 'split.artist'
          updset = {}
          ['composer', 'artist', 'album_artist'].each do |prop|
            value = atrack[prop]
            if value && !value.empty? && (value !~ /AC\&M/i)
              values = value.strip.split(/\s*[-,\&\/]\s*/)
              next unless (values.size > 1)
              nvalue = values.sort.join(', ')
              updset[prop] = nvalue
            end
          end
          atrack.updates(updset)
        when 'clean.composer'
          atrack.composer = atrack.composer.sub(/^.*:\s*/, '').
                sub(/\s*[\(\[].*$/, '')
        else
          Plog.error "Unsupported operation: #{instruction}"
          false
        end
      end
      true
    end
  end

  class ITuneHelper
    extendCli __FILE__

    # Build an index for the lyrics files
    def self.build_lyrics_index(dir = "./lyrics")
      LyricStore.build_index(dir)
    end

    def self.update_lyrics_if_changed(dir = "./lyrics")
      index = HashYaml.new("#{dir}/index.yml")
      index.each do |title, icontent|
        p title
      end
    end

    def self.sync_media(folder, *ddirs)
      icount  = (getOption(:incr) || 0).to_i
      fset    = ITuneFolder.new(folder).get_tracks.each do |atrack|
        atrack.enabled
      end
      Plog.info "Source list contains #{fset.size} files"

      csize   = 0
      outlist = {}
      Plog.info "Record to iTunes ..."
      ddirs.each do |dentry|
        dlist = []
        devdir = DeviceDir.new(dentry)
        while atrack = fset.shift
          unless devdir.try_add(atrack)
            next unless devdir.full
            fset.unshift(atrack)
            break
          end
        end

        outlist[devdir.dir] = devdir.wlist

        # Once we do this, track ref is changed by iTune, so no more track op
        if icount > 0
          devdir.tracks.each do |atrack|
            pcount = atrack.played_count || 0
            atrack.played_date.set(Time.now)
            atrack.played_count.set(pcount+1)
            STDERR.print "."
            STDERR.flush
          end
          STDERR.puts
        end
      end

      if ofile = getOption(:ofile)
        fod = File.open(ofile, "w")
      else
        fod = STDOUT
      end
      fod.puts outlist.to_yaml
      fod.close
      true
    end

    def self.copy_media(ymlfile)
      require 'find'

      config  = YAML.load_file(ymlfile)
      options = getOption

      if options[:purge]
        Pf.system "rm -rf #{config.keys.join(' ')}"
      else
        cflist = {}
        config.each do |ddir, content|
          # Scan all destination dirs for files
          Find.find(ddir) do |afile|
            next unless test(?f, afile)
            next if afile =~ /.(bmp|jpg)$/
            cflist[afile] = true
          end
          # Remove any files in the to updated list
          content.each do |sfile, dfile|
            cflist.delete(dfile)
          end
        end

        #---------------------- So whatever in the cflist is to be deleted ---
        if cflist.size > 0
          FileUtils.remove(cflist.keys, :verbose=>options[:verbose])
        end
      end

      config.each do |ddir, content|
        DeviceDir.new(ddir, options).copyfiles(content)
      end
      true
    end

    def self.add_images(dir)
      DeviceDir.new(dir, getOption).add_images
    end

    def self.rm_empty_dirs(dir = ".", level = 0)
      #Plog.info "[#{level}] Scanning #{dir}"
      rmit = true
      Dir.glob("#{dir}/*").sort.each do |afile|
        bfile = File.basename(afile)
        next if ['.', '..'].include?(bfile)
        if test(?d, afile)
          rm_empty_dirs("#{afile}", level+1)
        end
        if bfile !~ /\.jpg$/
          #Plog.info "Found #{bfile}.  Protect "#{dir}"
          rmit = false
        end
      end
      if rmit
        FileUtils.rm_rf(dir, :verbose=>true)
      else
        STDERR.print "."
        STDERR.flush
      end
      true
    end

    def self.update_if_changed(playlist, dir = "./lyrics")
      folder = ITuneFolder.new(playlist, getOption).update_if_changed(dir)
    end

    def self.track_run(playlist, *instructions)
      folder = ITuneFolder.new(playlist, getOption)
      instructions.each do |instruction|
        folder.track_run(instruction)
      end
      true
    end

    def self.stats(playlist, def_file = "stats.yml")
      ITuneFolder.new(playlist, getOption).stats(def_file)
    end

    def self.sub_artist(playlist, def_file = "artsub.yml")
      ITuneFolder.new(playlist, getOption).sub_artist(def_file)
    end

    def self.find_match(playlist)
      ITuneFolder.new(playlist, getOption).find_match
    end

    def self.add_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      options = getOption
      ITuneFolder.new(playlist, options).filter_list do |atrack, iname|
        LyricStore.new(src, exdir, atrack).set_track_lyric(options[:auto])
      end
      true
    end

    def self.clone_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
        LyricStore.new(src, exdir, atrack).store_to_track
      end
      true
    end

    def self.clear_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
        LyricStore.new(src, exdir, atrack).clear_track
      end
      true
    end

    def self.clone_composer(playlist, dbfile="./composer.yml")
      ITuneFolder.new(playlist, getOption).clone_composer(dbfile)
    end

    def self.nocomposer(playlist, startat=nil)
      wset = {}
      nset = {}
      pattern = getOption[:pattern]
      ITuneFolder.new(playlist).filter_list(pattern) do |atrack, iname|
        wset[iname] ||= 0
        wset[iname] += 1
        nset[iname] = atrack.name_clean
      end

      nwset = {}
      wset.each do |k, v|
        next unless wset[k] > 1
        nwset[k] = wset[k]
      end
      wset     = nwset
      count    = 0
      size     = wset.size
      lysource = LyricSource.new("yeucahat")
      wset.keys.sort.each do |k|
        count += 1
        v = wset[k]
        if startat
          next unless k > startat
        end
        lname = nset[k]
        puts "#{k}:\n  #{count}/#{size} = #{v} (#{lname})"
        Pf.system "open --background #{lysource.page_url(lname)}", 1
        puts "Hit enter to continue"
        STDIN.gets
      end
      nil
    end

    def self.check_missing_files(dir = ".")
      require 'find'

      skptn = Regexp.new(/.jpg$|.DS_Store$/)
      Find.find(dir) do |afile|
        next unless test(?f, afile)
        next if skptn.match(afile)
      end
    end
  end
end

if (__FILE__ == $0)
  ITune::ITuneHelper.handleCli(
        ['--auto',      '-a', 0],
        ['--cdir',      '-C', 1],
        ['--force',     '-f', 0],
        ['--incr',      '-i', 1],
        ['--init',      '-I', 0],
        ['--limit',     '-l', 1],
        ['--dryrun',    '-n', 0],
        ['--ofile',     '-o', 1],
        ['--purge',     '-p', 0],
        ['--pattern',   '-P', 1],
        ['--size',      '-S', 1],
        ['--tracks',    '-t', 1],
        ['--verbose',   '-v', 0]
  )
end

