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
      mchar = @@rmap[achar]
      result << (mchar || achar)
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
      file  = atrack.location.get.to_s
      album = atrack.album.get.gsub(/\//, '_')
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
        @kname = VnMap.to_ascii(name).sub(/\s*\(.*$/, '').strip
      end
      @kname
    end

    def updates(props, options = {})
      changed = false
      props.each do |prop, newval|
        curval = @track.send(prop).get
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
            @track.send(prop).set(newval)
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

    def method_missing(*args)
      @track.send(*args)
    end
  end

# Manage the external lyric store.  This is kept outside and clone
# into the tracks, b/c many tracks are of the same song, and it is
# too time consuming to get for each one.
  class LyricStore
    MIN_SIZE = 100

    # @param [String]     store Directory to store
    # @param [ITuneTrack] track iTune track
    def initialize(store, track)
      @store = store
      unless test(?d, store)
        FileUtils.mkdir_p(store, :verbose=>true)
      end

      @track = track

      name   = @track.name.get
      @kname = VnMap.to_ascii(name).sub(/\s*[-\(].*$/, '').strip
    end

    def value
      wfile  = "#{@store}/#{@kname}.txt"
      if test(?f, wfile)
        File.read wfile
      else
        ""
      end
    end

    def value=(content)
      wfile  = "#{@store}/#{@kname}.txt"
      Plog.info "Writing to #{wfile}"
      fod = File.open(wfile, "w")
      fod.puts content
      fod.close
    end

    def store_to_track
      clyrics = self.value
      if clyrics.size < MIN_SIZE
        Plog.info "No stored lyrics"
        return false
      end
      current = @track.lyrics.get
      if current.size >= MIN_SIZE
        Plog.info "#{@kname} already has lyrics.  Skip"
        return true
      end

      Plog.info "Setting lyrics for #{@kname}"
      @track.lyrics.set(clyrics)
      true
    end

    private
    def get_from_web
      require 'uri'
      require 'open-uri'

      name = @track.name.get.sub(/\s*[\-\(].*$/, '')
      cmd = "open --background 'http://www.video4viet.com/lyrics.html?act=search&q=#{URI.escape(name)}&type=title'"
      Pf.system(cmd, 1)
      STDOUT.puts "Enter content for lyrics [ = to end]: "
      content = []
      while line = STDIN.gets.chomp
        break if line =~ /^=/
        content << line
      end
      result = content.join("\n").strip
    end

    public
    # Set the lyrics content from web or store
    # @param [String] skipfile File containing list of name to skip.
    #   If we could not find in lyrics, it's no use keep repeating
    def set_from_web(skipfile)
      skiplist = HashYaml.new(skipfile)
      name     = @kname
      return if skiplist[name]
      return if store_to_track

      composer = @track.composer.get
      lyrics   = @track.lyrics.get
      album    = @track.album.get
      Plog.info "N: #{name}/#{album}, C: #{composer}"
      changed  = false
      if lyrics.empty? || (lyrics.size < MIN_SIZE)
        @track.reveal
        @track.play
        content = get_from_web
        if content.empty?
          skiplist[name] = true
          skiplist.save
        else
          Plog.info "Set webcontent to #{@track.name_clean}"
          @track.lyrics.set(content)
          self.value = content
          changed = true
        end
      end
      # Do it inside the look cause we use 'ctrl-c' to break out
      true
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
        composer = atrack.composer.get
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
        pattern = "#{atrack.name.get} #{atrack.artist.get}"
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
          value  = atrack.send(prop).get
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
        if !atrack.lyrics.get.empty?
          counters['has_lyrics'] += 1
        end
        if !atrack.composer.get.empty?
          counters['has_composer'] += 1
        end
        [:artist, :composer, :album_artist].each do |f|
          v = VnMap.to_ascii(atrack.send(f).get)
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
      self.filter_list do |atrack, iname|
        name    = atrack.name.get
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
            if !atrack.composer.get || atrack.composer.get.empty?
              updset[:composer] = composer
            end
            updset[:name] = tname
          end
          atrack.updates(updset)
        when 'b.artist'
          artist, title = atrack.name.get.split(/\s*-\s*/)
          next unless title
          atrack.updates(:name => title, :artist => artist)
        when 'a.artist'
          title, artist = atrack.name.get.split(/\s*-\s*/)
          next unless artist
          atrack.updates(:name => title, :artist => artist)
        # Capitalize name
        when 'cap'
          updset = {}
          ['name', 'artist', 'album_artist'].each do |prop|
            value  = atrack.send(prop).get
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
            value = atrack.send(prop).get
            if nvalue = SpecialName[value]
              updset[prop] = nvalue
            end
          end
          atrack.updates(updset)
        # General fix
        # Update Lien Khuc to LK
        # Remove all after -
        when 'clean_name'
          fixname = atrack.name.get.sub(/^Lien Khuc/i, 'LK').
                  sub(/^:/, '').
                  sub(/\s*-.*$/, '')
          if fixname =~ /^(.*)\s*\(.*$/
            fixname = $1
          end
          atrack.updates(:name => fixname)
        when 'fix_title'
          album, title = atrack.name.get.split(/\s*:\s*/, 2)
          atrack.updates(:name => title, :album => album)

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
        when 'split_artist'
          updset = {}
          ['artist', 'album_artist'].each do |prop|
            value = atrack.send(prop).get
            if value && !value.empty? && (value !~ /AC\&M/i)
              values = value.strip.split(/\s*[-,\&]\s*/)
              next unless (values.size > 1)
              nvalue = values.sort.join(', ')
              updset[prop] = nvalue
            end
          end
          atrack.updates(updset)
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

    def self.sync_media(folder, *ddirs)
      icount  = (getOption(:incr) || 0).to_i
      fset    = ITuneFolder.new(folder).get_tracks.each do |atrack|
        atrack.enabled.get
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
            pcount = atrack.played_count.get || 0
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

    def self.add_lyrics(playlist, skipfile="./skip.yml", exdir="./lyrics")
      ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
        LyricStore.new(exdir, atrack).set_from_web(skipfile)
      end
      true
    end

    def self.clone_lyrics(playlist, exdir="./lyrics")
      ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
        LyricStore.new(exdir, atrack).store_to_track
      end
      true
    end

    def self.clone_composer(playlist, dbfile="./composer.yml")
      ITuneFolder.new(playlist, getOption).clone_composer(dbfile)
    end

    def self.nocomposer(playlist, startat=nil)
      require 'uri'

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
      wset = nwset

      count = 0
      size = wset.size
      wset.keys.sort.each do |k|
        count += 1
        v = wset[k]
        if startat
          next unless k > startat
        end
        lname = nset[k]
        puts "#{k}:\n  #{count}/#{size} = #{v} (#{lname})"
        uri_lname = URI.escape(lname)
        cmd = "open 'http://www.video4viet.com/lyrics.html?act=search&q=#{uri_lname}&type=title'"
        Pf.system(cmd, 1)
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
        p afile
      end
    end
  end
end

if (__FILE__ == $0)
  ITune::ITuneHelper.handleCli(
        ['--cdir',      '-C', 1],
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

