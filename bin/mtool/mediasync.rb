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
require 'mtool/itunehelp'

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

class DeviceDir
  attr_reader :dir, :full, :tracks, :wlist

  def initialize(devspec, options={})
    @options    = options
    @dir, dsize = devspec.split(/:/)
    @maxsize    = dsize ? dsize.to_i*10 : 1_000_000_000
    @cursize    = 0
    @tracks     = []
    @full       = false
    @wlist      = []
  end

  def try_add(atrack)
    file  = atrack.location.get.path
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

class MediaSync
  def initialize(folder, ddirs, options = {})
    require 'appscript'

    @app     = Appscript::app('iTunes')
    @folder  = folder
    @ddirs   = ddirs
    @options = options
  end

  def prepare
    icount  = (@options[:incr] || 0).to_i
    fset    = ITune::ITuneFolder.new(@folder).get_tracks.each do |atrack|
      atrack.enabled
    end
    Plog.info "Source list contains #{fset.size} files"

    csize   = 0
    outlist = {}
    Plog.info "Record to iTunes ..."
    @ddirs.each do |dentry|
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
    outlist
  end

  def transfer(config)
    require 'find'

    if @options[:purge]
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
        FileUtils.remove(cflist.keys, :verbose=>@options[:verbose])
      end
    end

    config.each do |ddir, content|
      DeviceDir.new(ddir, @options).copyfiles(content)
    end
    true
  end

  def sync
    transfer(prepare)
  end

  def add_images
    @ddirs.each do |dentry|
      DeviceDir.new(dentry, @options).add_images
    end
  end
end

class MediaSyncCli
  extendCli __FILE__

  def self.sync(folder, *ddirs)
    MediaSync.new(folder, ddirs, getOption).sync
  end

  def self.add_images(*ddirs)
    MediaSync.new("", ddirs, getOption).add_images
  end
end

if (__FILE__ == $0)
  MediaSyncCli.handleCli(
        ['--cdir',      '-C', 1],
        ['--incr',      '-i', 1],
        ['--purge',     '-p', 0],
        ['--size',      '-S', 1],
        ['--verbose',   '-v', 0]
  )
end

