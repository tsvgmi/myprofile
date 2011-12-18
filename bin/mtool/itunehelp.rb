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
require 'mtool/vnmap'

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

# Manage iTune tracks and update access via iTune app interface.
# Wrapper so accessor would be more ruby like
  class ITuneTrack
    attr_accessor :track

    # @param track The Itune track object
    def initialize(track, options = {})
      @track   = track
      @options = options
      @kname   = nil
    end

    # Return the clean name. (Remove VN accent and modifier)
    def name_clean
      unless @kname
        name   = @track.name.get
        @kname = name.vnto_ascii.sub(/\s*[-\(].*$/, '').strip
      end
      @kname
    end

    # Updating one or more track properties.
    # Only update if there is change
    # @param [Hash] props Properties to update
    # @param [Hash] options Updating options
    # @option options :dryrun Print only but no change
    def updates(props)
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
        unless @options[:dryrun]
          self[prop] = newval
        end
      end
      changed
    end

    # Printing track info to stdout
    def show
      composer = @track.composer.get
      artist   = @track.artist.get
      album    = @track.album.get
      Plog.info "N:#{name_clean}/#{album}, C:#{composer}, A:#{artist}"
    end

    # @param [Symbol] property Track property name
    # @return [String] Value of the specified property
    def [](property)
      result = @track.send(property).get
      if result == :missing_value
        result = ""
      end
      result
    end

    # @param [Symbol] property Track property name
    # @param [String] value New value to set to track property
    def []=(property, value)
      if value.is_a?(String)
        value = value.strip
      end
      begin
        @track.send(property).set(value)
      rescue => errmsg
        p errmsg
      end
    end

    # Map the applescript set/get to ruby attribute reference and assign.
    # Simpler to use.
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

# Manage the external lyric store.  This is kept outside and clone
# into the tracks, b/c many tracks are of the same song, and it is
# too time consuming to get for each one.
  class LyricStore
    MIN_SIZE = 400

    # @param [String]     store Directory to store
    # @param [ITuneTrack] track iTune track
    def initialize(src, store, track, options = {})
      require 'mtool/lyricsource'

      @app     = ITuneApp.app
      @store   = store
      @options = options
      unless test(?d, store)
        FileUtils.mkdir_p(store, :verbose=>true)
      end
      @track = track

      name      = @track.name
      @kname    = name.vnto_ascii.sub(/\s*[-\(].*$/, '').strip
      @source   = src
      @lysource = LyricSource.get(src, @options)
      @wfile    = "#{@store}/#{@kname}.2txt"
    end

# @return [String] Content of lyric in store.  Text format
    def value
      if test(?f, @wfile)
        YAML.load_file(@wfile)[:content]
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
      if content
        Plog.info "Writing to #{@wfile}"
        fod = File.open(@wfile, "w")
        fod.puts({
          :source  => @source,
          :content => content
        }.to_yaml)
        fod.close
      else
        if test(?f, @wfile)
          FileUtils.remove(@wfile, :verbose=>true)
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
        chset = @lysource.extract_metadata(clyrics)
        if chset.size > 0
          Plog.info "Setting lyric for #{@kname}"
          @track.updates(chset)
        end
        # Protect since web may send down bad encoded string?
        begin
          @track.lyrics  = clyrics
        rescue => errmsg
          begin
            @track.lyrics = clyrics.vnto_ascii
          rescue => errmsg
            Plog.error errmsg
          end
        end
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

    def auto_get
      @lysource.auto_get(@track)
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
      unless @options[:force]
        return if skiplist[name]
        return if store_to_track
      end

      composer = @track.composer
      lyrics   = @track[:lyrics]
      album    = @track.album
      changed  = false
      @track.show
      if @options[:force] || lyrics.empty? || (lyrics.size < MIN_SIZE)
        if auto
          content = @lysource.auto_get(@track)
        else
          @track.reveal
          @track.play
          content = @lysource.manual_get(@track)
        end
        if content.empty?
          skiplist[name] = true
          skiplist.save
        else
          Plog.info "Set webcontent to #{@track.name_clean}"
          self.value = content
          changed    = store_to_track
        end
      end
      # Do it inside the look cause we use 'ctrl-c' to break out
      true
    end

    def edit(rw = true)
      require 'tempfile'

      if @options[:store]
        wset = [self.value, @track.lyrics]
      else
        wset = [@track.lyrics, self.value]
      end

      lyrics = nil
      wset.each do |alyrics|
        unless alyrics.strip.empty?
          lyrics = alyrics.strip
          break
        end
      end

      unless lyrics
        Plog.info "No lyrics found for #{@track.name} to edit"
        return false
      end

      # Cache it
      if self.value.empty?
        self.value = lyrics
      end

      @fod = Tempfile.new("it")
      @fod.puts lyrics
      @fod.close
      @song_path = @fod.path

      @start_time = Time.now
      Plog.info "Editing lyrics for #{@track.name}"
      if rw
        cmd = "open -FnWt #{@song_path}"
        Pf.system(cmd, 1)
        check_and_update
      else
        cmd = "open -a TextMate #{@song_path}"
        Pf.system(cmd, 1)
      end
      true
    end

    def check_and_update
      if File.mtime(@song_path) > @start_time
        curtrack  = @app.current_track.get
        stopfirst = (@track.track == curtrack)

        @app.pause if stopfirst
        content = File.read(@song_path)
        Plog.info "Setting lyrics for #{@track.name} back to track"
        self.value = content
        @track.updates(
          :comment => Time.now.strftime("%y.%m.%d.%H.%M.%S"),
          :lyrics  => content
        )
        @start_time = Time.now
        @app.play if stopfirst
      end
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
          :artist     => artist.vnto_ascii.sub(/\s*\(.*$/, ''),
          :raw_artist => artist
        }
      end
      index.save
    end
  end

  class EditServer
    def initialize(exdir = "./lyrics", options = {})
      @exdir   = exdir
      @options = {}
    end

    def monitor
      curtrack = nil
      folder = ITuneFolder.new("play", @options)
      edsongs = []
      while true
        atrack = folder.get_tracks(true).first
        btrack = ITuneTrack.new(atrack, @options)
        if !curtrack || (btrack.name != curtrack.name)
          curtrack = btrack
          edsong = LyricStore.new("console", @exdir, btrack, @options)
          if edsong.edit(false)
            edsongs << edsong
          end
        end
        Plog.info("Waiting for #{edsongs.size} edits ...")
        sleep(5)
        edsongs.each do |asong|
          asong.check_and_update
        end
      end
      true
    end

  end

  # Manage itune collections.  Collection could be a playlist, a playlist
  # folder, current set, selection, or a searched list.
  class ITuneFolder
    attr_reader :tracks         # List of selected tracks

    # Create a new collection
    #
    # @param [String] name Collection name.  It could be 'current' for
    #   current view, 'select' for the currently selected items.  Otherwise,
    #   it is a playlist name.
    # @param [Hash] options Extra options
    # @option options [String] :pattern Specify a pattern to select a subset of
    #   the collection.
    # @option options [Integer] :limit (100000) Max number of matching tracks
    # @option options [Boolean] :verbose Verbose log
    # @option options [Boolean] :force
    def initialize(name, options={})
      @name    = name
      @app     = ITuneApp.app
      @ifolder = nil
      @options = options
      @tracks  = []
      Plog.info "Using folder #{@name}"
      get_tracks(true, @options[:pattern])
    end

    # Collect the list of matching tracks
    def get_tracks(reset = false, ptn = nil)
      if reset
        case @name
        when "current"
          @ifolder = @app.browser_windows[1].view
        when "select"
          @ifolder = @app.selection
        when "play"
          @ifolder = @app.current_track
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
      end
      if ptn
        Plog.info "Search for #{ptn}"
        @tracks = @ifolder.search :for=>ptn.gsub(/\./, ' ')
      elsif @name == "select"
        @tracks = @ifolder.get
      elsif @name == "play"
        @tracks = [@ifolder.get]
      else
        @tracks = @ifolder.tracks.get
      end
      @tracks
    end

    # Iterator though each matching track
    def each_track
      limit = (@options[:limit] || 100000).to_i
      @tracks.each do |atrack|
        atrack = ITuneTrack.new(atrack, @options)
        if yield atrack, atrack.name_clean.downcase
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
      self.each_track do |atrack, iname|
        composer = atrack.composer
        changed  = false
        if composer.empty?
          if wset[iname] && (wset[iname].size > 0)
            changed |= atrack.updates(:composer => wset[iname].first)
          end
        else
          wset[iname] ||= composer.vnto_ascii
        end
        changed
      end
      wset.save
    end

    SpecialName = {
      'Abba'  => 'ABBA',
      'Ac, M' => 'AC&M',
      'Maya'  => 'MayA'
    }

    def find_match
      mainFolder = ITuneFolder.new('Music', @options)
      self.each_track do |atrack, iname|
        atrack.show
        pattern = "#{atrack.name} #{atrack.artist}"
        mainFolder.get_tracks(false, pattern)
        mainFolder.each_track do |mtrack, mname|
          mtrack.show
        end
      end
      true
    end

    def sub_artist(subfile)
      subdefs = YAML.load_file(subfile)
      self.each_track do |atrack, iname|
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
      self.each_track do |atrack, iname|
        if !atrack.composer.empty?
          counters['has_composer'] += 1
        end
        [:artist, :composer, :album_artist].each do |f|
          v = atrack[f].vnto_ascii
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
      self.each_track do |atrack, iname|
        tname   = atrack.name.vnto_ascii.sub(/\s*\(.*$/, '')
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
          LyricStore.new("video4viet", dir, atrack, @options).
                store_to_track(true)
        end
      end
    end

    def track_run(instruction)
      ntracks  = @options[:tracks] || @tracks.size
      curtrack = 0
      updopts  = {
        :overwrite => @options[:overwrite]
      }
      self.each_track do |atrack, iname|
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
            nvalue = value.cap_words
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
                  sub(/\s*[-\(].*$/, '')
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
        when 'clean.name'
          atrack.name = atrack.name.split(/\s*-\s*/, 2)[1]
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

    def self.auto_get(playlist, src="yeucahat", exdir="./lyrics")
      options = getOption
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricStore.new(src, exdir, atrack, options).auto_get
      end
      true
    end

    def self.add_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      options = getOption
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricStore.new(src, exdir, atrack, options).
                set_track_lyric(options[:auto])
      end
      true
    end

    def self.edit_lyrics(playlist = "play", exdir="./lyrics")
      options = getOption
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricStore.new("console", exdir, atrack, options).edit
      end
      true
    end

    def self.monitor_lyrics(exdir = "./lyrics")
      EditServer.new(exdir).monitor
    end

    def self.clone_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      options = getOption
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricStore.new(src, exdir, atrack, options).store_to_track
      end
      true
    end

    def self.clear_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      options = getOption
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricStore.new(src, exdir, atrack, options).clear_track
      end
      true
    end

    def self.clone_composer(playlist, dbfile="./composer.yml")
      ITuneFolder.new(playlist, getOption).clone_composer(dbfile)
    end

    def self.nocomposer(playlist, startat=nil)
      require 'mtool/lyricsource'

      wset = {}
      nset = {}
      pattern = getOption[:pattern]
      ITuneFolder.new(playlist).each_track(pattern) do |atrack, iname|
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
      lysource = LyricSource.get("yeucahat")
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

    def self.run(*args)
      app = ITuneApp.app
      app.send(*args)
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
        ['--new',       '-N', 0],
        ['--ofile',     '-o', 1],
        ['--purge',     '-p', 0],
        ['--pattern',   '-P', 1],
        ['--store',     '-s', 0],
        ['--size',      '-S', 1],
        ['--tracks',    '-t', 1],
        ['--verbose',   '-v', 0]
  )
end

