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

class ITuneHelper
  extendCli __FILE__

  def initialize
    require 'appscript'

    @itunes = Appscript::app('iTunes')
  end

  def folder_content(folder)
    ifolder = nil
    p @itunes
    @itunes.folder_playlists.get.each do |afolder|
      if afolder.name.get == folder
        ifolder = afolder
        break
      end
    end
    unless ifolder
      Plog.error "Folder #{folder} not found"
      return []
    end
    result = []
    ifolder.file_tracks.get.each do |atrack|
      result << atrack
    end
    result
  end

  def sync_media(folder, *ddirs)
    fset   = []
    icount = (ITuneHelper.getOption(:incr) || 0).to_i
    fset   = folder_content(folder)
    Plog.info "Attempt to transfer #{fset.size} files"

    csize   = 0
    outlist = {}
    Plog.info "Record to iTunes ..."
    ddirs.each do |dentry|
      dlist = []
      ddir, dsize = dentry.split(/:/)
      p dentry
      dsize = dsize ? dsize.to_i*10 : 1_000_000_000
      while atrack = fset.shift
        begin
          file  = atrack.location.get.to_s
          album = atrack.album.get.gsub(/\//, '_')
          unless test(?f, file)
            p file, album
            next
          end
          fsize = (File.size(file)+99999)/100000
          csize += fsize
          if (csize >= dsize)
            fset.unshift(atrack)
            csize = 0
            break
          end
          dfile = "#{ddir}/#{album}/#{File.basename(file)}"
          dlist << [file, dfile, album]
          if icount > 0
            pcount = atrack.played_count.get
            pcount ||= 0
            atrack.played_count.set(pcount+1)
            #atrack.played_date.set(Time.now)
            STDERR.print "."
            STDERR.flush
          end
        rescue Appscript::CommandError => errmsg
          p errmsg
        end
      end
      outlist[ddir] = dlist
    end
    STDERR.puts
    if ofile = ITuneHelper.getOption(:ofile)
      fod = File.open(ofile, "w")
    else
      fod = STDOUT
    end
    fod.puts outlist.to_yaml
    fod.close
    true
  end

  def copy_media(ymlfile)
    require 'find'

    config = YAML.load_file(ymlfile)

    verbose = ITuneHelper.getOption(:verbose)
    if getOption(:purge)
      Pf.system "rm -rf #{config.keys.join(' ')}"
    else
      cflist = {}
      config.each do |ddir, content|
        Find.find(ddir) do |afile|
          next unless test(?f, afile)
          cflist[afile] = true
        end
        content.each do |sfile, dfile|
          cflist.delete(dfile)
        end
      end
      if cflist.size > 0
        FileUtils.remove(cflist.keys, :verbose=>verbose)
      end
    end

    config.each do |ddir, content|
      content.each do |sfile, dfile|
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
          FileUtils.mkpath(ddir, :verbose=>verbose)
        end
        FileUtils.cp(sfile, dfile, :verbose=>verbose)
      end
    end
    true
  end

  def self.add_img(dir, size = "100x100")
    require 'find'

    options = getOption
    verbose = options[:verbose]
    cdir    = options[:cdir] || "./images"
    unless test(?d, cdir)
      FileUtil.mkpath(cdir, :verbose=>verbose)
    end
    dircount  = {}
    photoinfo = PhotoInfo.new
    `find #{dir}`.split("\n").each do |afile|
      next if afile =~ /.(bmp|jpg)$/
      next if afile =~ /#{dir}$/
      if test(?f, afile)
        wdir   = File.dirname(afile)
        dircount[wdir] ||= 0
        dircount[wdir] += 1
      else
        dircount[afile] ||= 0
        dircount[afile] += 1
        next
      end
      album  = File.split(wdir).last.gsub(/\'/, '')
      cvfile = "#{wdir}/cover.jpg"
      unless test(?f, cvfile)
        m3info = Mp3Shell.new(afile, options)
        cafile = "images/#{album}-#{size}.jpg"
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
    dircount.keys.sort.each do |k|
      v = dircount[k]
      next if k == dir
      if v <= 1
        FileUtils.rm_rf(k, :verbose=>true)
      end
    end
    true
  end

  def self.rm_empty_dirs(*dirs)
    require 'find'

    dirs.each do |adir|
      protect = false
      Find.find(adir) do |afile|
        next unless test(?f, afile)
        if afile !~ /\.(ini|jpg|DS_Store)$/
          protect = true
          puts "#{afile} should be protected from #{adir}"
          break
        end
      end
      unless protect
        FileUtils.rm_rf(adir, :verbose=>true)
      end
    end
  end

  def self.cliNew
    new
  end
end

if (__FILE__ == $0)
  ITuneHelper.handleCli(
        ['--cdir',   '-C', 1],
        ['--incr',   '-i', 1],
        ['--ofile',  '-o', 1],
        ['--purge',  '-p', 0],
        ['--server', '-s', 0],
        ['--verbose', '-v', 0],
        ['--wait',   '-w', 1]
  )
end

