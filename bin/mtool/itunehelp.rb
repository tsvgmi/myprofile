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

class PhotoInfo
  def initialize
    require 'find'

    @images = []
    Find.find("#{ENV['HOME']}/dump/images") do |afile|
      if afile =~ /\.jpg$/
        @images << afile
      end
    end
  end

  def mk_thumbnail(ofile, size)
    rndfile = @images[rand(@images.size)]
    Pf.system("convert '#{rndfile}' -adaptive-resize #{size} '#{ofile}'", 1)
    test(?f, ofile)
  end
end

class ITuneApp
  @@app = nil

  def self.app
    require 'appscript'

    unless @@app
      Plog.info "Connect to iTunes"
      @@app = Appscript::app('iTunes')
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

class ItTrack
  attr_accessor :track

  def initialize(track)
    @track = track
    @kname = nil
  end

  def name_clean
    @track.name.get.sub(/\s*[\-\(].*$/, '')
  end

  def name_key
    require 'iconv'

    unless @kname
      name = @track.name.get
      name = begin
        Iconv.iconv('US//IGNORE//TRANSLIT', 'UTF-8', name).to_s
      rescue Iconv::IllegalSequence => errmsg
        name.gsub(/[^&a-z._0-9 -]/i, "").tr(".", "_")
      end
      @kname = name.downcase.gsub(/['`\.\?~^aeiou]/, '')
    end
    @kname
  end

  def cache_lyrics(exdir)
    wfile  = "#{exdir}/#{self.name_clean}.txt"
    if test(?f, wfile)
      Plog.info "#{wfile} found. Skip"
      return false
    end

    lyrics = @track.lyrics.get
    if (lyrics == :missing_value) || lyrics.empty?
      return false
    end

    Plog.info "Writing to #{wfile}"
    fod = File.open(wfile, "w")
    fod.puts lyrics
    fod.close
    true
  end

  def clone_lyrics(exdir)
    wfile  = "#{exdir}/#{self.name_clean}.txt"
    unless test(?f, wfile)
      #Plog.info "Skip #{wfile}. Not found"
      STDERR.print "."; STDERR.flush
      return false
    end

    lyrics = @track.lyrics.get
    unless (lyrics == :missing_value) || lyrics.empty?
      return false
    end

    Plog.info "Setting lyrics from #{wfile}"
    @track.lyrics.set(File.read(wfile))
    true
  end

  def method_missing(*args)
    @track.send(*args)
  end
end

class ITuneFolder
  def initialize(name, options={})
    require 'appscript'

    @app     = Appscript::app('iTunes')
    @ifolder = nil
    @options = options
    [@app.folder_playlists, @app.playlists].each do |alist|
      alist.get.each do |afolder|
        #puts afolder.name.get
        if afolder.name.get == name
          @ifolder = afolder
          break
        end
      end
      break if @ifolder
    end
    unless @ifolder
      raise "Folder #{name} not found"
    end
  end

  def each
    result = []
    if @ifolder
      @ifolder.file_tracks.get.each do |atrack|
        if yield(atrack)
          result << atrack
        end
      end
    end
    result
  end

  def filter_list
    ptn = @options[:pattern]
    if ptn
      ptn = ptn.gsbu(/[aeiou]/i, '')
      ptn = Regexp.new(/^#{ptn}$/i)
    else
      ptn = Regexp.new('.')
    end
    self.each do |atrack|
      atrack2  = ItTrack.new(atrack)
      name_key = atrack2.name_key
      if ptn.match(name_key)
        yield atrack2, name_key
      end
    end
  end

  def get_lyrics(track)
    require 'uri'
    require 'open-uri'

    name = track.name.get.sub(/\s*[\-\(].*$/, '')
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

  def extract_lyrics(exdir="./lyrics")
    unless test(?d, exdir)
      FileUtils.mkdir_p(extdir, :verbose=>true)
    end
    self.filter_list do |atrack, iname|
      atrack.cache_lyrics(exdir)
    end
    true
  end

  def clone_lyrics(exdir="./lyrics")
    unless test(?d, exdir)
      FileUtils.mkdir_p(extdir, :verbose=>true)
    end
    self.filter_list do |atrack, iname|
      atrack.clone_lyrics(exdir)
    end
    true
  end

  def add_lyrics(skipfile=nil, exdir="./lyrics")
    if skipfile && test(?f, skipfile)
      skiplist = YAML.load_file(skipfile)
    else
      skiplist = {}
    end
    self.filter_list do |atrack, iname|
      name     = atrack.name_clean
      next if skiplist[name]
      composer = atrack.composer.get
      lyrics   = atrack.lyrics.get
      puts "N: #{name}, C: #{composer}"
      if lyrics.empty?
        content = get_lyrics(atrack)
        if content.empty?
          skiplist[name] = true
        else
          atrack.lyrics.set(content)
          atrack.cache_lyrics(exdir)
        end
      end
      # Do it inside the look cause we use 'ctrl-c' to break out
      if skipfile
        fod = File.open(skipfile, "w")
        fod.puts skiplist.to_yaml
        fod.close
      end
    end
  end

  def clone_composer(dbfile=nil)
    compname = {}
    if dbfile && !@options[:init] && test(?f, dbfile)
      compname = YAML.load_file(dbfile)
    end

    self.filter_list do |atrack, iname|
      composer = atrack.composer.get
      if composer.empty?
        if composer = compname[iname]
          puts ">>#{composer}: #{iname}"
          atrack.composer.set(composer)
        end
      else
        #puts "#{composer}: #{iname}"
        STDERR.print('.'); STDERR.flush
        compname[iname] ||= composer
      end
    end
    if dbfile
      fod = File.open(dbfile, "w")
      fod.puts compname.to_yaml
      fod.close
    end
  end
end

class ITuneHelper
  extendCli __FILE__

  def self.sync_media(folder, *ddirs)
    icount  = (getOption(:incr) || 0).to_i
    fset    = ITuneFolder.new(folder).each do |atrack|
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

  def self.rm_empty_dirs(*dirs)
    dirs.each do |adir|
      DeviceDir.new(adir).rm_empty_dirs
    end
  end

  def self.num2track(playlist)
    ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
      name = atrack.name.get
      if name =~ /^(\d+)\.?\s*/
        rname = $'
        track = $1.to_i
        puts "#{name} => T: #{track}. #{rname}"
        atrack.track_number.set(track)
        atrack.name.set(rname)
      end
    end
  end
  
  def self.add_composer(playlist, *icomposer)
    composer = icomposer.join(' ')
    ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
      puts "#{iname} => #{composer}"
      if icomposer.size > 0
        atrack.composer.set(composer)
      end
    end
  end

  def self.showtracks(playlist)
    ITuneFolder.new(playlist, getOption).filter_list do |atrack, iname|
      composer = atrack.composer.get
      name     = atrack.name_clean
      lyrics   = atrack.lyrics.get
      puts "N: #{name}, C: #{composer}, L: #{lyrics}"
    end
  end

  def self.clone_composer(playlist, dbfile=nil)
    ITuneFolder.new(playlist, getOption).clone_composer(dbfile)
  end

  def self.add_lyrics(playlist, skipfile=nil, exdir="./lyrics")
    ITuneFolder.new(playlist, getOption).add_lyrics(skipfile, exdir)
  end

  def self.extract_lyrics(playlist, exdir="./lyrics")
    ITuneFolder.new(playlist, getOption).extract_lyrics(exdir)
  end

  def self.clone_lyrics(playlist, exdir="./lyrics")
    ITuneFolder.new(playlist, getOption).clone_lyrics(exdir)
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
end

if (__FILE__ == $0)
  ITuneHelper.handleCli(
        ['--cdir',    '-C', 1],
        ['--incr',    '-i', 1],
        ['--init',    '-I', 0],
        ['--ofile',   '-o', 1],
        ['--purge',   '-p', 0],
        ['--pattern', '-P', 1],
        ['--size',    '-S', 1],
        ['--server',  '-s', 0],
        ['--verbose', '-v', 0],
        ['--wait',    '-w', 1]
  )
end

