#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: itunehelp.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'rubygems'
require 'mtool/lyricstore'
require 'yaml'
require 'fileutils'
require 'tempfile'
require 'mtool/core'
require 'mtool/mp3file'
require 'mtool/vnmap'
require 'mtool/dbaccess'
require 'appscript'

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
      unless @@app
        ITuneHelper.notify "#{File.basename(__FILE__)} connecting to iTunes"
        #@@app = Appscript::app.by_name('iTunes', Tunes)
        @@app = Appscript::app('iTunes')
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

    def has_lyric?
      tlyrics = @track.lyrics.get
      tlyrics.size >= 400
    end

    def set_lyric(storetrack)
      @track.lyrics.set(storetrack[:content])
      if storetrack[:composer] && @track.composer.get.empty?
        tcomposer = storetrack[:composer]
        if tcomposer.is_a?(Array)
          tcomposer = tcomposer.first
        end
        @track.composer.set(tcomposer)
      end
      if @track.name.get !~ /[\(\[]/
        if storetrack[:name] && !storetrack[:name].empty?
          tname = storetrack[:name]
          if tname.is_a?(Array) 
            tname = tname.first
          end
          @track.name.set(tname)
        end
      end
      @track.comment.set(Time.now.strftime("%y.%m.%d.%H.%M.%S"))
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
          if true
            @ifolder = @app.folder_playlists[@name]
          else
            @ifolder = @app.playlists[@name]
          end
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

    def sizeof
      tsize = 0
      self.each_track do |atrack, iname|
        bsize = ((atrack[:size] + 2047)/2048)*2048
        puts "%8d %8d %s" % [atrack[:size], bsize, atrack[:name]]
        tsize += bsize
      end
      tsize
    end

    def print_lyrics(prefix = "lyrics")
      processed = {}
      self.each_track do |atrack, iname|
        if processed[iname]
          Plog.info "Skip repeated #{atrack[:name]}"
          next
        end
        processed[iname] = true
        lyrics           = atrack[:lyrics]
        if (lyrics.size < 200)
          Plog.warn "No lyrics found in #{iname}"
          next
        end
        name   = atrack[:name]
        lyrics = lyrics.gsub(/[\n]/, "\n").split(/\n/)
        title  = "#{name} - #{atrack[:artist]} - #{atrack[:grouping]}"
        ofile  = "#{iname}.txt".gsub(/\s+/, '_')
        fod = File.open(ofile, "w")
        fod.puts title
        fod.puts
        fod.puts lyrics
        fod.close
        Plog.info "File #{ofile} written"
      end
      true
    end

    def print_content
      self.each_track do |atrack, iname|
        puts "| %-20.20s | %-10.10s | %-10.10s |" %
                [atrack[:name], atrack[:composer], atrack[:grouping]]
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

    def track_run(instruction)
      ntracks  = @options[:tracks] || @tracks.size
      curtrack = 0
      updopts  = {
        :overwrite => @options[:overwrite]
      }
      if @options[:query]
        @options[:dryrun] = true
      end
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
        when 'x.name.artist', 'x.artist.name'
          name   = atrack.name
          artist = atrack.artist
          next unless name
          atrack.updates(:name => artist, :artist => name)
        when 'artist.name'
          artist, title = atrack.name.split(/\s*[-\/]\s*/)
          next unless title
          atrack.updates(:name => title, :artist => artist)
        # Track in form of title - artist
        when 'name.artist'
          title, artist = atrack.name.split(/\s*[-_]\s*/, 2)
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
              values = value.strip.split(/\s*[-_,\&\/]\s*/)
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
        when 'clean.album'
          atrack.updates(:album => atrack.album.gsub(/_/, ' '))
        when 'clean.name'
          fixname = atrack.name.sub(/^Lien Khuc/i, 'LK').
                  sub(/^:/, '').
                  sub(/\s*[-\(].*$/, '').strip
          atrack.updates(:name => fixname)
        else
          Plog.error "Unsupported operation: #{instruction}"
          false
        end
      end
      if @options[:query]
        if Cli.confirm "OK to apply the change"
          @options.delete(:dryrun)
          @options.delete(:query)
          track_run(instruction)
        end
      end
      true
    end
  end

  class ITuneHelper
    extendCli __FILE__

    def self.handle_common_options
      options = getOption
      if options[:verbose]
        Plog.level = Logger::DEBUG
      end
      options
    end

    def self.track_run(playlist, *instructions)
      options = handle_common_options
      folder  = ITuneFolder.new(playlist, options)
      instructions.each do |instruction|
        folder.track_run(instruction)
      end
      true
    end

    def self.stats(playlist, def_file = "stats.yml")
      options = handle_common_options
      ITuneFolder.new(playlist, options).stats(def_file)
    end

    def self.sub_artist(playlist, def_file = "artsub.yml")
      options = handle_common_options
      ITuneFolder.new(playlist, options).sub_artist(def_file)
    end

    def self.find_match(playlist)
      options = handle_common_options
      ITuneFolder.new(playlist, options).find_match
    end

    # Add lyrics to itune files (using MP3 tag)
    def self.add_lyrics(playlist, srcs="yeucahat", exdir="./lyrics")
      options = handle_common_options
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        if atrack.has_lyric? && !options[:force]
          Plog.info "#{atrack[:name]} already has lyric.  Skip"
          next
        end
        srcs.split(/,/).each do |src|
          if storetrack = LyricCache.new(src, exdir, atrack, options).get_lyric
            atrack.set_lyric(storetrack)
            break
          end
        end
      end
      true
    end

    def self.export_lyrics(playlist, exdir="./lyrics")
      options = handle_common_options
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricCache.new(src, exdir, atrack, options).track_to_cache
      end
      true
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

    def self.clear_lyrics(playlist, src="yeucahat", exdir="./lyrics")
      options = handle_common_options
      ITuneFolder.new(playlist, options).each_track do |atrack, iname|
        LyricCache.new(src, exdir, atrack, options).clear_lyric
      end
      true
    end

    def self.print_lyrics(playlist)
      options = handle_common_options
      ITuneFolder.new(playlist, options).print_lyrics
    end

    def self.sizeof(playlist)
      options = handle_common_options
      ITuneFolder.new(playlist, options).sizeof
    end

    def self.print_content(playlist, exdir="./content")
      options = handle_common_options
      ITuneFolder.new(playlist, options).print_content
    end

    def self.clone_composer(playlist, dbfile="./composer.yml")
      options = handle_common_options
      ITuneFolder.new(playlist, options).clone_composer(dbfile)
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
      #Pf.system "growlNotify --appIcon iTunes --message '#{msg}'", 1
      Plog.info msg
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
        ['--query',     '-q', 0],
        ['--store',     '-s', 0],
        ['--size',      '-S', 1],
        ['--tracks',    '-t', 1],
        ['--verbose',   '-v', 0]
  )
end

