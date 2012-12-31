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
require 'tempfile'
require 'mtool/core'
require 'mtool/mp3file'
require 'mtool/vnmap'
require 'mtool/dbaccess'
require 'mtool/tunes'

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
    tmpf = Tempfile.new("hy")
    tmpf.puts(@content.to_yaml)
    tmpf.close
    if test(?f, @yfile)
      FileUtils.move(@yfile, "#{@yfile}.bak", :force=>true, :verbose=>true)
    end
    FileUtils.move(tmpf.path, @yfile, :force=>true, :verbose=>true)
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
        ITuneHelper.notify "#{File.basename(__FILE__)} connecting to iTunes"
        @@app = Appscript::app.by_name('iTunes', Tunes)
        #@@app.activate
      end
      @@app
    end

    # Prepare for updating the specified track
    #
    # Some parameters will not update unless the currently played song is
    # stopped.
    # @param track ITune Track to check for
    def self.prepare_track_update(track)
      itune    = self.app
      begin
        curtrack = itune.current_track.get
        if (track == curtrack)
          invisual = itune.visuals_enabled.get
          Plog.debug "Pausing play"
          itune.pause
          yield

          #--- Toggle visual to refresh lyric --- 
          if invisual
            Plog.debug "Toggle visual"
            itune.visuals_enabled.set(false)
            itune.visuals_enabled.set(true)
          end
          Plog.debug "Resuming play"
          itune.play
        else
          yield
        end
      rescue => errmsg
        p errmsg
        yield
      end
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
      @kname ||= self.class.name_clean(@track.name.get)
      @kname
    end

    def self.name_clean(string)
      string.vnto_ascii.sub(/\s*[-\(].*$/, '').downcase.strip
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
      @track   = track
      @kname   = @track.name_clean
      @wfile   = "#{@store}/#{@kname}.2txt"

      unless test(?d, store)
        FileUtils.mkdir_p(store, :verbose=>true)
      end

      if src
        @source = src
      else
        self.value
        @source = @fsrc || src
      end
      @lysource = LyricSource.get(@source, @options)
      @_value   = ""
    end

# @return [String] Content of lyric in store.  Text format
    def value
      if !@value || @_value.empty?
        if test(?f, @wfile)
          data   = YAML.load_file(@wfile)
          Plog.debug("Loading lyrics from #{@wfile}")
          @fsrc  = data[:source]
          @_value = data[:content]
        else
          wfile  = "#{@store}/#{@kname}.txt"
          if test(?f, wfile)
            Plog.debug("Loading lyrics from #{wfile}")
            @_value = File.read wfile
          end
        end
      end
      @_value
    end

# @param [String] content Content to set to lyric text in store
    def value=(content)
      if content && !content.empty?
        Plog.info "Writing #{@kname} to #{@wfile}"
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
      @_value = content
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
          Plog.debug "Setting attr for #{@kname} from lyrics - #{chset.to_yaml}"
          @track.updates(chset)
        end
        # Protect since web may send down bad encoded string?
        Plog.info "Updating track lyrics"
        ITuneApp.prepare_track_update(@track.track) do
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
        end
        Plog.info "Updated"
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
      skiplist = @lysource.skiplist || {}
      name     = @kname
      unless @options[:force]
        return if skiplist[name]
        return if store_to_track(true)
      end

      composer = @track.composer
      lyrics   = @track[:lyrics]
      album    = @track.album
      changed  = false
      @track.reveal
      #@track.show
      if @options[:force] || lyrics.empty? || (lyrics.size < MIN_SIZE)
        if auto
          content = @lysource.auto_get(@track)
          #sleep(3)
        else
          #@track.reveal
          @track.play
          content = @lysource.manual_get(@track)
        end
        if content.empty?
          skiplist[name] = true
        else
          Plog.info "Set webcontent to #{@track.name_clean}"
          self.value = content
          changed    = store_to_track(@options[:force])
        end
      end
      changed
    end

    def edit(edfile = nil, wait = true)
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
        Plog.debug "No lyrics found for #{@track.name} to edit"
        return false
      end

      # Cache it
      if self.value.empty?
        self.value = lyrics
      end

      unless edfile
        # Need to keep the tmp file around, or it get wiped
        @fod = Tempfile.new("it")
        @fod.puts lyrics
        @fod.close
        @song_path = @fod.path
      else
        fod = File.open(edfile, "w")
        fod.puts lyrics
        fod.close
        @song_path = edfile
      end

      @start_time = Time.now
      ITuneHelper.notify "Editing lyrics for #{@track.name}"
      cmd = @options[:editor] ? "open -a #{@options[:editor]}" : "open"
      unless wait
        Pf.system("#{cmd} #{@song_path}", 1)
      else
        Pf.system("#{cmd} -FnWt #{@song_path}", 1)
        check_and_update
      end
      true
    end

    def check_and_update
      if File.mtime(@song_path) > @start_time
        content = File.read(@song_path)
        ITuneHelper.notify "Setting lyrics for #{@track.name} into track"
        self.value = content
        if content.strip.empty?
          clear_track
        else
          store_to_track(true)
        end
        @start_time = Time.now
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

    def self.edit_all(playlist = "play", exdir="./lyrics", options = {})
      edsongs = []

      options[:limit] ||= 10

      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        edsong = LyricStore.new(nil, exdir, atrack, options)
        if edsong.edit(nil, false)
          edsongs << edsong
        end
      end
      unless edsongs.size > 0
        return false
      end
      while true
        _edcheck(edsongs, options)
      end
      true
    end

    # Just wait around for track change and
    def self.edit_server(exdir = "./lyrics", options = {})
      curname, edsong = nil, nil
      folder   = ITuneFolder.new("play", options)
      tmpfile  = Tempfile.new("it")
      while true
        if btrack = folder.get_tracks(true).first
          if !curname || (btrack.name != curname)
            Plog.debug "Detect track change to '#{btrack.name}'"
            curname = btrack.name
            chksong = LyricStore.new("console", exdir, btrack, options)
            if chksong.edit(tmpfile.path, false)
              edsong = chksong
            end
          end
        end
        _edcheck([edsong], options)
      end
      true
    end

    def self._edcheck(edsongs, options)
      interval = (options[:interval] || 5).to_i
      Plog.debug("Waiting for edit ...")
      sleep(interval)
      _src_reload_check
      edsongs.each do |edsong|
        edsong.check_and_update if edsong
      end
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
          @ifolder = @app.playlists[@name]
        end
        unless @ifolder
          raise "Folder #{@name} not found"
        end
      end
      itracks = []
      begin
        if ptn
          Plog.debug "Search for #{ptn}"
          itracks = @ifolder.search :for=>ptn.gsub(/\./, ' ')
        elsif @name == "select"
          itracks = @ifolder.get
        elsif @name == "play"
          itracks = [@ifolder.get]
        else
          itracks = @ifolder.tracks.get
        end
      rescue => errmsg
        p errmsg
      end
      @tracks = itracks.map {|t| ITuneTrack.new(t, @options)}
    end

    # Iterator though each matching track
    def each_track
      limit = (@options[:limit] || 100000).to_i
      @tracks.each do |atrack|
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

    def _dump_lyrics(names, lydata, prefix)
      name0 = names[0].gsub(/[\s\']+/, '_').sub(/^(a|an|the)\s+/i, '')[0..2]
      name9 = names[-1].gsub(/[\s\']+/, '_').sub(/^(a|an|the)\s+/i, '')[0..2]
      cfile = "#{prefix}-#{name0}-#{name9}.txt"
      Plog.info "Writing to #{cfile}"
      fod   = File.open(cfile, "w")
      fod.puts "{{toc}}\n\n"
      names.each do |name|
        fod.puts lydata[name]
      end
      fod.close
    end

    def print_lyrics(prefix = "lyrics")
      lydata    = {}
      processed = {}
      fcount    = 0
      songs     = []
      self.each_track do |atrack, iname|
        if processed[iname]
          Plog.info "Skip repeated #{atrack[:name]}"
          next
        end
        processed[iname] = true
        lyrics           = atrack[:lyrics]
        next if (lyrics.size < 200)
        name = atrack[:name]
        lyrics = lyrics.gsub(/
/, "\n").split(/\n/)
        result = []
        bpara  = true
        lyrics.each do |l|
          if bpara
            if l.strip.empty?
              result << l
            else
              result << "p=. #{l}"
              bpara = false
            end
          else
            if l.strip.empty?
              bpara = true
            end
            result << l
          end
        end
        title  = "\nh2. #{name} - #{atrack[:artist]} - #{atrack[:grouping]}\n\n"
        lydata[iname] = title + "\n" + result.join("\n")
        songs << iname
        STDERR.print ".#{lydata.size}"
        STDERR.flush
        if lydata.size >= 100
          _dump_lyrics(songs, lydata, prefix)
          lydata = {}
          songs  = []
        end
      end
      if lydata.size > 0
        _dump_lyrics(songs, lydata, prefix)
      end
      true
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
        ['artist', 'album_artist', 'composer'].each do |prop|
          value  = atrack[prop]
          nvalue = value.split(/\s*,\s*/).sort.map do |avalue|
            subdefs.each do |k, v|
              avalue = avalue.sub(/^#{k}$/i, v)
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
        when 'name.composer'
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
        when 'artist.name'
          artist, title = atrack.name.split(/\s*-\s*/)
          next unless title
          atrack.updates(:name => title, :artist => artist)
        # Track in form of title - artist
        when 'name.artist'
          title, artist = atrack.name.split(/\s*-\s*/)
          next unless artist
          atrack.updates(:name => title, :artist => artist)
        when 'track.artist.name'
          updset = {}
          if name =~ /^(\d+)\s*[-\.]?\s*/
            trackno = $1.to_i
            artist, title = $'.split(/\s*-\s*/, 2)
            updset[:track_number] = trackno
            updset[:name]         = title
            updset[:artist]       = artist
            atrack.updates(updset)
          end
        when 'track.name.artist'
          updset = {}
          if name =~ /^(\d+)\s*[-\.]?\s*/
            trackno = $1.to_i
            title, artist = $'.split(/\s*-\s*/, 2)
            updset[:track_number] = trackno
            updset[:name]         = title
            updset[:artist]       = artist
            atrack.updates(updset)
          end
        when 'track.name'
          updset = {}
          if name =~ /^(\d+)\s*[-\.]?\s*/
            trackno = $1.to_i
            title   = $'
            updset[:track_number] = trackno
            updset[:name]         = title
            atrack.updates(updset)
          end
        when 'name.group'
          title, group = atrack.name.split(/\s*[-\(\)]\s*/)
          next unless group
          atrack.updates(:name => title, :grouping => group)
        when 'name.group.artist'
          title, group, tmp, artist = atrack.name.split(/\s*[-\(\)]\s*/)
          next unless group
          atrack.updates(:name => title, :artist=>artist, :grouping => group)
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
                  sub(/\s*[-\(].*$/, '').strip
          atrack.updates(:name => fixname)

        # Remove the track info in front of name and move to track
        when 'number.track'
          updset = {}
          if name =~ /^(\d+)\s*[-\.]?\s*/
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
        when 'splitcap'
          updset = {}
          ['name', 'artist'].each do |prop|
            value = atrack[prop]
            nvalue = value.scan(/[A-Z][a-z]+/).join(' ')
            updset[prop] = nvalue
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

    def self.add_lyrics(playlist, srcs="yeucahat", exdir="./lyrics")
      options = getOption
      if options[:verbose]
        Plog.level = Logger::DEBUG
      end
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        srcs.split(/,/).each do |src|
          if LyricStore.new(src, exdir, atrack, options).
                  set_track_lyric(options[:auto])
            break
          end
        end
      end
      true
    end

    def self.edit_lyrics(playlist = "play", exdir="./lyrics")
      LyricStore.edit_all(playlist, exdir, getOption)
    end

    def self.clone_meta
      options = getOption
      tracks = ITuneFolder.new("select", options).get_tracks
      if (tracks.size % 2) != 0
        raise "Must have even tracks to clone"
      end
      while tracks.size > 0
        if tracks[0].date_added > tracks[1].date_added
          new_track, old_track = *tracks
        else
          old_track, new_track = *tracks
        end
        if old_track.size > (new_track.size + 3000000)
          Plog.warn "Track #{new_track.name} is smaller (#{old_track.size} - #{new_track.size}).  Skip"
          tracks = tracks[2..-1]
          next
        end
        puts "Transfer meta from #{old_track.name}/#{old_track.album} to #{new_track.name}/#{new_track.album}"
        cset = {
          :played_count => old_track.played_count + new_track.played_count,
          :rating       => old_track.rating,
          :lyrics       => old_track.lyrics,
          :comment      => old_track.comment
        }
        if new_track.album.strip.empty?
          cset[:album] = old_track.album
        end
        new_track.updates(cset)
        old_track.updates(:rating => 20)
        tracks = tracks[2..-1]
      end
    end

    def self.monitor_lyrics(exdir = "./lyrics")
      options = getOption
      if options[:verbose]
        Plog.level = Logger::DEBUG
      end
      LyricStore.edit_server(exdir, options)
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

    def self.print_lyrics(playlist, exdir="./lyrics")
      ITuneFolder.new(playlist, getOption).print_lyrics
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

    def self.notify(msg)
      Pf.system "growlNotify --appIcon iTunes --message '#{msg}'", 1
    end

    def self.load_song_db
      options = getOption
      DB::Song.transaction do
        DbAccess.execute "delete from songs"
        ITuneFolder.new("Music", options).each_track do |atrack, iname|
          oname  = atrack.name.gsub(/'/, "''")
          oiname = iname.gsub(/'/, "''")
          sql    = "insert into songs(name,name_clean) values('#{oname}', '#{oiname}')"
          begin
            DbAccess.execute(sql)
          rescue => errmsg
            p errmsg
            p atrack.name, iname
          end
        end
      end
      true
    end

    def self.load_skip_db(*files)
      options   = getOption
      files.each do |file|
        source    = File.basename(file).sub(/\..*$/, '')
        source_id = DB::Source.find_by_name(source)[:id]
        DB::SkipLyric.transaction do
          YAML.load_file(file).each do |name, val|
            name_clean = ITuneTrack.name_clean(name)
            if (song_rec = DB::Song.find_by_name_clean(name_clean))
              sql = "replace into skiplyrics(source_id,song_id)
                    values(#{source_id},#{song_rec[:id]})"
              DbAccess.execute(sql)
            end
          end
        end
      end
      true
    end

  end
end

def _src_reload_check
  unless @_sreload
    @_sreload = Time.now
  end
  if File.mtime(__FILE__) > @_sreload
    Plog.debug "#{__FILE__} changed.  Reload"
    $0 = ""
    load __FILE__
    @_sreload = Time.now
  end
end

if (__FILE__ == $0)
  DbAccess.connect('itune')
  ITune::ITuneHelper.handleCli(
        ['--auto',      '-a', 0],
        ['--cdir',      '-C', 1],
        ['--editor',    '-E', 1],
        ['--force',     '-f', 0],
        ['--interval',  '-i', 1],
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

