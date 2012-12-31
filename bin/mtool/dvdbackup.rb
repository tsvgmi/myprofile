#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'fileutils'
require 'tempfile'
require 'mtool/core'

class FileSet
  def initialize(fset, options = {})
    @fset    = fset
    @options = options
  end

  def backup_to(target)
    ofile = "#{target}.iso"
    if test(?e, ofile)
      if @options[:force]
        FileUtils.rm(ofile, :verbose=>true, :force=>true)
      else
        Plog.error "#{ofile} exist, skip"
        return nil
      end
    end

    Plog.info "Backup #{@fset.size} files to #{ofile}"
    wdir = "/tmp/#{File.basename(target)}"
    FileUtils.rm_rf(wdir, :verbose=>true)
    pfod = File.popen("cpio -pamvd #{wdir}", "w")
    pfod.puts @fset.join("\n")
    pfod.close

    unless Pf.system("hdiutil makehybrid -o #{ofile} #{wdir}", 1)
      return nil
    end

    FileUtils.rm_rf(wdir, :verbose=>true)
    return ofile
  end
end

class WorkDir
  def initialize(dir, options = {})
    @options = options
    Plog.info "Scanning #{dir}"
    if test(?f, dir)
      @files = File.read(dir).split("\n").sort
    else
      @files = `find #{dir} -type f`.split("\n").sort
    end
    Plog.info "Found #{@files.size} files"
  end

  def each_slice(per_slice)
    per_slice = per_slice * 1000000
    cursize   = 0
    curset    = []
    if incptn = @options[:include]
      incptn = Regexp.new(/#{incptn}/i)
    end
    @files.each do |afile|
      if incptn
        next unless incptn.match(File.basename(afile))
      end
      fsize = ((File.size(afile) + 2047)/2048)*2048
      cursize += fsize
      if cursize > per_slice
        yield FileSet.new(curset, @options)
        cursize = 0
        curset  = []
      end
      curset << afile
    end
    if curset.size > 0
      yield FileSet.new(curset, @options)
    end
  end

  def backup_set(size)
    numdisk = 0
    ofiles  = []
    each_slice(size) do |aslice|
      Plog.info "Backup disk ##{numdisk+1}"
      wtarget = "%s-%02d" % [target, numdisk]
      unless ofile = aslice.backup_to(wtarget)
        Plog.info "Error creating backup #{wtarget}"
        break
      end
      if @options[:burn]
        DVDBackup._burn_disk(ofile)
        FileUtils.rm(ofile, :verbose=>true)
      end
      ofiles << ofile
      numdisk += 1
    end
    Plog.info "Backed up to #{ofiles.size} #{size}M disks"
    return ofiles
  end
end

# Helper for vnc script.
class DVDBackup
  extendCli __FILE__

  # example
  # dvdbackup.rb -i "mp3|m4a" backup_set ~/music.log /tmp/dvd
  def self.backup_set(src, target)
    if size = getOption(:size)
      size = size.to_i
    else
      size = 4500
    end
    WorkDir.new(src, getOption).backup_set(size)
  end

  # example
  # dvdbackup.rb burn_images -p8 dvd-01.iso
  def self.burn_images(*isofiles)
    isofiles.each do |afile|
      _burn_disk(afile, getOption)
    end
  end

  def self._burn_disk(afile, options = {})
    bopt = ""
    unless options[:verify]
      bopt += " -noverifyburn"
    end
    if speed = options[:speed]
      bopt += " -speed #{speed}"
    end
    Pf.system("hdiutil burn #{bopt} #{afile}", 1)
  end
end

if (__FILE__ == $0)
  DVDBackup.handleCli(
    ['--burn',    '-b', 0],
    ['--force',   '-f', 0],
    ['--include', '-i', 1],
    ['--speed',   '-p', 1],
    ['--size',    '-s', 1],
    ['--verify',  '-v', 0],
    ['--exclude', '-x', 1]
  )
end

